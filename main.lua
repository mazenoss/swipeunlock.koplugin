--[[--
Swipe to open

Puts a "Swipe to open" slider on top of the sleep screen: when the device is woken up with
the physical button, a round button appears on the left of a bar reading "Swipe to open".
The device only opens once the button has been dragged to the right.

This builds on KOReader's own "keep the sleep screen up after waking" machinery
(Settings > Screen > Sleep screen > Wake-up settings), by swapping the stock lock widget for
our slider (see swipeunlockwidget.lua).
]]

local Device = require("device")

if not Device:isTouchDevice() then
    return { disabled = true, }
end

local InputDialog = require("ui/widget/inputdialog")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local Screensaver = require("ui/screensaver")
local SwipeUnlockWidget = require("swipeunlockwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local SETTING_ENABLED = "swipe_unlock_enabled" -- nil means enabled
local SETTING_TEXT = "swipe_unlock_text"

local function isEnabled()
    return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

local function getText()
    local text = G_reader_settings:readSetting(SETTING_TEXT)
    if text and text ~= "" then
        return text
    end
end

-- Run func(...) with the "keep the sleep screen up after waking" setting forced to "gesture",
-- and put the user's own setting back right after.
local function withForcedLock(func, ...)
    local key = "screensaver_delay"
    local previous = G_reader_settings:readSetting(key)
    G_reader_settings:saveSetting(key, "gesture")
    local ok, res = pcall(func, ...)
    if previous == nil then
        G_reader_settings:delSetting(key)
    else
        G_reader_settings:saveSetting(key, previous)
    end
    if not ok then
        error(res, 0)
    end
    return res
end

-- These patches are applied once, when the plugin is loaded, and are inert when the plugin is
-- switched off in its menu (everything checks isEnabled() when it runs).
local function patch()
    if Screensaver._swipe_unlock_patched then
        return
    end
    Screensaver._swipe_unlock_patched = true

    -- 1. Whatever the user's settings, ask the Screensaver to create its lock widget when going
    --    to sleep, and to keep it up when waking (that's the "gesture" mode).
    local orig_show = Screensaver.show
    Screensaver.show = function(self, ...)
        -- Only for actual sleep (not for the poweroff/reboot screens)
        if not isEnabled() or (self.prefix and self.prefix ~= "") then
            return orig_show(self, ...)
        end
        local res = withForcedLock(orig_show, self, ...)
        self._swipe_unlock_forced = self.screensaver_lock_widget ~= nil
        return res
    end

    local orig_close = Screensaver.close
    Screensaver.close = function(self, ...)
        if self._swipe_unlock_forced and self.screensaver_lock_widget then
            return withForcedLock(orig_close, self, ...)
        end
        return orig_close(self, ...)
    end

    -- 2. Have the lock widget be our slider.
    local orig_new = ScreenSaverLockWidget.new
    ScreenSaverLockWidget.new = function(cls, o)
        if isEnabled() then
            local args = {}
            for k, v in pairs(o or {}) do
                args[k] = v
            end
            args.text = getText()
            local ok, widget = pcall(SwipeUnlockWidget.new, SwipeUnlockWidget, args)
            if ok and widget then
                return widget
            end
            -- Never risk leaving the device without a way to wake up: use the stock widget.
            logger.err("SwipeUnlock: falling back to the stock lock widget:", widget)
        end
        return orig_new(cls, o)
    end
end

patch()

local SwipeUnlock = WidgetContainer:extend{
    name = "swipeunlock",
    is_doc_only = false,
}

function SwipeUnlock:init()
    self.ui.menu:registerToMainMenu(self)
end

function SwipeUnlock:changeText(touchmenu_instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Text of the slider"),
        input = getText() or SwipeUnlockWidget.DEFAULT_TEXT,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Default"),
                    callback = function()
                        G_reader_settings:delSetting(SETTING_TEXT)
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Set"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText()
                        if text == "" or text == SwipeUnlockWidget.DEFAULT_TEXT then
                            G_reader_settings:delSetting(SETTING_TEXT)
                        else
                            G_reader_settings:saveSetting(SETTING_TEXT, text)
                        end
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function SwipeUnlock:addToMainMenu(menu_items)
    menu_items.swipe_unlock = {
        text = _("Swipe to open"),
        sorting_hint = "screen",
        sub_item_table = {
            {
                text = _("Ask to swipe when waking up"),
                help_text = _([[When the device wakes up, a "Swipe to open" slider is shown on top of the sleep screen. Drag its button to the right to open KOReader.

This replaces the setting "Keep the sleep screen up after wake-up".]]),
                checked_func = isEnabled,
                callback = function()
                    G_reader_settings:flipNilOrTrue(SETTING_ENABLED)
                end,
            },
            {
                text = _("Text of the slider"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:changeText(touchmenu_instance)
                end,
            },
            {
                text = _("Preview the slider"),
                callback = function()
                    -- The menu closes itself after this callback returns: show the slider afterwards.
                    UIManager:nextTick(function()
                        UIManager:show(SwipeUnlockWidget:new{
                            is_preview = true,
                            text = getText(),
                        })
                    end)
                end,
            },
        },
    }
end

return SwipeUnlock
