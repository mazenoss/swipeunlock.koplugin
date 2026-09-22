--[[--
Swipe-to-open slider, drawn on top of the sleep screen.

While the device sleeps this widget sits (invisible) on top of the sleep screen.
When the device wakes up (Resume event) it paints a "slide to unlock"-like bar at the
bottom of the screen: a round button on the left and a bar with a text on its right.
Dragging the button far enough to the right dismisses the sleep screen.

It is created in place of the stock ScreenSaverLockWidget (see main.lua), and mimics its
contract: it's a modal widget, it flips Device.screen_saver_lock on Resume/Suspend, and
it closes the Screensaver widget when unlocked.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local DEFAULT_TEXT = _("Swipe to open")

local SwipeUnlockWidget = InputContainer:extend{
    name = "SwipeUnlock",
    DEFAULT_TEXT = DEFAULT_TEXT,
    modal = true, -- stay on top of the sleep screen (and of everything else)
    invisible = true, -- UIManager must ignore us, refresh-wise, until we're woken up
    stop_events_propagation = true,
    is_swipe_unlock = true,
    text = nil, -- text of the bar
    is_preview = false, -- true when shown from the menu, over the regular UI
    unlock_ratio = 0.55, -- how far (0..1) the button must travel to open the device
}

function SwipeUnlockWidget:init()
    self.text = (self.text and self.text ~= "") and self.text or DEFAULT_TEXT
    self.slider_visible = false
    self.knob_offset = 0 -- distance travelled by the button, in pixels
    self.grab_dx = 0
    self.dragging = false
    self.paint_failed = false

    if Device:isTouchDevice() then
        local pan_rate = Screen.low_pan_rate and 3.0 or 8.0
        local function full_screen()
            return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        end
        self.ges_events = {
            Touch = { GestureRange:new{ ges = "touch", range = full_screen } },
            Pan = { GestureRange:new{ ges = "pan", rate = pan_rate, range = full_screen } },
            HoldPan = { GestureRange:new{ ges = "hold_pan", rate = pan_rate, range = full_screen } },
            PanRelease = { GestureRange:new{ ges = "pan_release", range = full_screen } },
            HoldRelease = { GestureRange:new{ ges = "hold_release", range = full_screen } },
            Swipe = { GestureRange:new{ ges = "swipe", range = full_screen } },
            Multiswipe = { GestureRange:new{ ges = "multiswipe", range = full_screen } },
            Tap = { GestureRange:new{ ges = "tap", range = full_screen } },
        }
    end

    if self.is_preview then
        self.slider_visible = true
        self.invisible = false
    end
end

--- Geometry of everything we draw. Computed lazily (and again if the screen size changes,
--- e.g., the sleep screen was rotated to portrait after we were built).
function SwipeUnlockWidget:_buildLayout(sw, sh)
    local L = { sw = sw, sh = sh }
    local side = math.floor(sw * 0.07)
    local pad = Screen:scaleBySize(6)

    L.ks = math.floor(math.min(sw, sh) * 0.13) -- diameter of the round button
    L.th = L.ks + 2 * pad -- height of the bar
    L.tw = sw - 2 * side -- width of the bar
    L.tx = side
    L.ty = sh - math.floor(sh * 0.09) - L.th
    L.border = Size.border.thick
    L.track_radius = math.floor(L.th / 2)
    L.knob_radius = math.floor(L.ks / 2)

    L.kx0 = L.tx + pad -- resting position of the button
    L.ky = L.ty + pad
    L.travel = math.max((L.tx + L.tw - pad - L.ks) - L.kx0, 1)
    L.hit_pad = math.floor(L.ks * 0.5) -- be generous with fingers

    local icon_size = math.floor(L.ks * 0.6)
    L.icon_dx = math.floor((L.ks - icon_size) / 2)
    L.icon = IconWidget:new{
        icon = "chevron.right",
        width = icon_size,
        height = icon_size,
        invert = true, -- white chevron on the black button
    }

    -- The text lives in the bar, to the right of the button's resting place.
    local text_x0 = L.kx0 + L.ks + pad
    local text_x1 = L.tx + L.tw - math.floor(L.th / 2)
    local avail = math.max(text_x1 - text_x0, 1)
    L.text_widget = TextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = avail,
    }
    local tsize = L.text_widget:getSize()
    L.text_x = text_x0 + math.floor((avail - tsize.w) / 2)
    L.text_y = L.ty + math.floor((L.th - tsize.h) / 2)
    return L
end

function SwipeUnlockWidget:_freeLayout()
    local L = self._layout
    if not L then return end
    self._layout = nil
    if L.icon then L.icon:free() end
    if L.text_widget then L.text_widget:free() end
end

function SwipeUnlockWidget:_getLayout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local L = self._layout
    if L and L.sw == sw and L.sh == sh then
        return L
    end
    self:_freeLayout()
    local ok, res = pcall(self._buildLayout, self, sw, sh)
    if not ok then
        logger.err("SwipeUnlock: failed to build the slider:", res)
        self.paint_failed = true -- escape hatch: a tap will open the device
        return nil
    end
    self._layout = res
    return res
end

function SwipeUnlockWidget:_getRegion()
    local L = self:_getLayout()
    if L then
        return Geom:new{ x = L.tx, y = L.ty, w = L.tw, h = L.th }
    end
    return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end

function SwipeUnlockWidget:_refresh(refresh_type)
    UIManager:setDirty(self, function()
        return refresh_type, self:_getRegion()
    end)
end

function SwipeUnlockWidget:_paint(bb)
    local L = self:_getLayout()
    if not L then return end

    -- The bar is fully opaque, so we can repaint it as often as we want
    -- without having to repaint the sleep screen below us.
    bb:paintRoundedRect(L.tx, L.ty, L.tw, L.th, Blitbuffer.COLOR_WHITE, L.track_radius)
    bb:paintBorder(L.tx, L.ty, L.tw, L.th, L.border, Blitbuffer.COLOR_BLACK, L.track_radius)

    L.text_widget:paintTo(bb, L.text_x, L.text_y)

    -- The button, on top of the text
    local kx = L.kx0 + self.knob_offset
    bb:paintRoundedRect(kx, L.ky, L.ks, L.ks, Blitbuffer.COLOR_BLACK, L.knob_radius)
    L.icon:paintTo(bb, kx + L.icon_dx, L.ky + L.icon_dx)
end

function SwipeUnlockWidget:paintTo(bb, x, y)
    if not self.slider_visible then return end
    local ok, err = pcall(self._paint, self, bb)
    if not ok then
        logger.err("SwipeUnlock: paint failed:", err)
        self.paint_failed = true
    end
end

-- Gestures -------------------------------------------------------------------

function SwipeUnlockWidget:_offsetFromX(L, x)
    local offset = math.floor(x - self.grab_dx - L.kx0)
    if offset < 0 then return 0 end
    if offset > L.travel then return L.travel end
    return offset
end

function SwipeUnlockWidget:onTouch(_, ges)
    if not self.slider_visible then return true end
    local L = self:_getLayout()
    if not L then return true end
    local pos = ges.pos
    local kx = L.kx0 + self.knob_offset
    local hit = L.hit_pad
    if pos.x >= kx - hit and pos.x <= kx + L.ks + hit
       and pos.y >= L.ky - hit and pos.y <= L.ky + L.ks + hit then
        self.dragging = true
        self.grab_dx = pos.x - kx
    else
        self.dragging = false
    end
    return true
end

function SwipeUnlockWidget:onPan(_, ges)
    if not (self.slider_visible and self.dragging) then return true end
    local L = self:_getLayout()
    if not L then return true end
    local offset = self:_offsetFromX(L, ges.pos.x)
    if offset ~= self.knob_offset then
        self.knob_offset = offset
        self:_refresh("fast")
    end
    return true
end
SwipeUnlockWidget.onHoldPan = SwipeUnlockWidget.onPan

-- Finger lifted: pan_release, hold_release, swipe or multiswipe
function SwipeUnlockWidget:onRelease(_, ges)
    if not self.dragging then return true end
    self.dragging = false
    local L = self:_getLayout()
    if not L then return true end
    -- swipes report their *starting* point as pos, and the lift point as end_pos
    local x = ges.end_pos and ges.end_pos.x or ges.pos.x
    local offset = self:_offsetFromX(L, x)
    if offset >= L.travel * self.unlock_ratio then
        self.knob_offset = offset
        self:unlock()
    elseif self.knob_offset ~= 0 then
        -- Not far enough: the button goes back to its place
        self.knob_offset = 0
        self:_refresh("ui")
    end
    return true
end
SwipeUnlockWidget.onPanRelease = SwipeUnlockWidget.onRelease
SwipeUnlockWidget.onHoldRelease = SwipeUnlockWidget.onRelease
SwipeUnlockWidget.onSwipe = SwipeUnlockWidget.onRelease
SwipeUnlockWidget.onMultiswipe = SwipeUnlockWidget.onRelease

function SwipeUnlockWidget:onTap(_, ges)
    if self.paint_failed then
        -- We couldn't draw the slider: don't lock the user out.
        self:unlock()
    elseif self.is_preview then
        -- Tapping anywhere but on the bar dismisses the preview
        local L = self:_getLayout()
        local pos = ges.pos
        if not L or pos.x < L.tx or pos.x > L.tx + L.tw or pos.y < L.ty or pos.y > L.ty + L.th then
            self:unlock()
        end
    end
    -- Otherwise, taps do nothing: one has to swipe.
    return true
end

-- Unlocking -----------------------------------------------------------------

function SwipeUnlockWidget:unlock()
    return self:onClose()
end

function SwipeUnlockWidget:onClose(arg)
    if arg and arg.keep_screensaver then return true end -- poweroff, reboot

    if self.is_preview then
        UIManager:close(self, "ui", self:_getRegion())
        return true
    end

    if self.orig_dimen and self.ui then -- sleep screen was rotated
        self.ui:updateTouchZonesOnScreenResize(self.orig_dimen)
    end
    -- Go quiet *before* closing, so that UIManager doesn't refresh the bare sleep screen
    -- between us going away and the Screensaver widget going away.
    self.slider_visible = false
    self.invisible = true
    UIManager:close(self)
    -- Close the actual Screensaver, if any
    local Screensaver = require("ui/screensaver")
    if Screensaver.screensaver_widget then
        Screensaver.screensaver_widget:onClose()
    end
    return true
end
-- That's the Event Dispatcher will send us ;)
SwipeUnlockWidget.onExitScreensaver = SwipeUnlockWidget.onClose

function SwipeUnlockWidget:onCloseWidget()
    self:_freeLayout()
    if self.is_preview then return end
    -- If we don't have a ScreenSaverWidget, request a full repaint to get rid of our bar,
    -- and take care of the Screensaver's cleanup in its place, too.
    local Screensaver = require("ui/screensaver")
    if not Screensaver.screensaver_widget then
        UIManager:setDirty("all", "full")
        Screensaver:cleanup()
    end
end

function SwipeUnlockWidget:onShow()
    if self.is_preview then
        self:_refresh("ui")
    end
end

-- Power management ------------------------------------------------------------

-- The device just woke up: this is our cue.
function SwipeUnlockWidget:onResume()
    if self.is_preview then return end
    -- Tell Device that further Power button presses while we're shown must send us back to suspend
    Device.screen_saver_lock = true
    self.knob_offset = 0
    self.dragging = false
    self.slider_visible = true
    self.invisible = false
    self:_refresh("ui")
end

-- Going back to sleep without having been unlocked: show the bare sleep screen again.
function SwipeUnlockWidget:onSuspend()
    if self.is_preview then return end
    Device.screen_saver_lock = false
    if self.slider_visible then
        self.slider_visible = false
        self.invisible = true
        self.dragging = false
        self.knob_offset = 0
        UIManager:setDirty("all", "full")
    end
end

return SwipeUnlockWidget
