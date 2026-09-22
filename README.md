# Swipe to open

A [KOReader](https://github.com/koreader/koreader) plugin that replaces the plain sleep screen
with a "swipe to open" slider — the same idea as a phone's lock screen.

When you wake the device with the physical power button, a bar appears at the bottom of the
screen with a round button on the left and the text **"Swipe to open"** on the right. Drag the
button to the right to unlock the device and go back to KOReader. Let go too early and the
button springs back; the sleep screen stays up until you actually swipe it open.

## Installation

1. Download this repository (or just the `swipeunlock.koplugin` folder).
2. Copy the `swipeunlock.koplugin` folder into KOReader's `plugins/` directory.
   - On most platforms that's `koreader/plugins/swipeunlock.koplugin`.
   - On Kobo/Kindle/etc., it's wherever `koreader/plugins/` lives on the device — see
     [KOReader's plugin docs](https://github.com/koreader/koreader/wiki/Plugins) if you're not
     sure where that is on your device.
3. Restart KOReader.
4. The plugin is on by default. You can turn it off, change the bar's text, or preview it from
   `Settings → Screen → Swipe to open`.

## Usage

- Put the device to sleep as usual (power button, or auto-suspend).
- Press the power button to wake it up.
- Drag the round button to the right until it reaches roughly the far end of the bar to unlock.
- If you stop dragging before that point, the button snaps back and the device stays asleep.
- Tapping the screen (without dragging) does nothing — you have to swipe.
- Pressing the power button again while the slider is up puts the device back to sleep.

## Settings

Found under **Settings → Screen → Swipe to open**:

- **Ask to swipe when waking up** — turn the whole feature on or off. When off, KOReader
  behaves as it would without this plugin installed.
- **Text of the slider** — customize the label shown on the bar (defaults to "Swipe to open").
- **Preview the slider** — show the slider on top of the current screen, without having to put
  the device to sleep first, so you can check how it looks.

## How it works

The plugin hooks into KOReader's existing sleep-screen machinery (`ui/screensaver.lua`) rather
than replacing it:

- It temporarily forces the "keep sleep screen up after wake-up" delay mode (internally called
  `"gesture"`) for the duration of each sleep cycle, without touching your own saved setting.
- It substitutes its own draggable widget (`swipeunlockwidget.lua`) for KOReader's built-in,
  invisible lock widget.
- If anything goes wrong building or drawing the slider, it falls back to KOReader's normal
  lock screen (or, in the worst case, lets a tap unlock the device) so you're never locked out.

## Compatibility

- Requires a touchscreen device (the plugin disables itself on non-touch devices).
- Tested against the current KOReader `master` APIs (`ui/screensaver.lua`,
  `ui/widget/screensaverlockwidget.lua`, `ui/uimanager.lua`) as of this writing. KOReader's
  internal APIs aren't guaranteed stable, so a future KOReader update could require adjustments.

## Known limitations

- The drag must start on the round button itself, not anywhere on the bar or screen.
- On e-ink, the button's motion is stepped rather than smooth, following KOReader's own
  "low pan rate" screen setting.
- The bar's size and position are computed from the screen dimensions and aren't yet
  user-configurable beyond the text.

## License

Same license as KOReader itself (AGPL-3.0), unless you decide otherwise for this repository.
