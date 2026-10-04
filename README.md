# ennUI 1.0

A minimal, text-based home screen for KOReader.

## Install
Copy the `ennui.koplugin` folder into KOReader's `plugins` folder (replacing your
current version) and restart KOReader. Disable any other home screen plugin (for
example Simple UI) while using ennUI. Your existing settings carry over.

## What's new in 1.0
- Renamed throughout to **ennUI** (the capitalization you'll see everywhere
  it's displayed — toasts, menu titles, the plugin listing).
- The Plugin entries "Max entries per page" setting now reads
  **"Auto-fit to page"** instead of "No limit" when no cap is set.
- KOReader's top menu (Tools) now has a single **"ennUI"** entry, which takes
  you to the home screen. The separate "ennUI settings" entry is gone — swipe
  up from the bottom of the home screen for Settings, as in the last version.

## Use
- Swipe up from the bottom edge of the home screen, any time, to open ennUI
  Settings.
- Settings lists: Date, Clock, Weather, Plugin entries, Section order,
  Wallpaper, Extras, and the version at the bottom. Tapping any of the first
  four opens: Enabled, Alignment, Padding, Text Style, Drop Shadow / Outline,
  plus whatever's specific to that item:
  - Clock: Show AM/PM (the clock is always 12-hour).
  - Weather: ZIP code, country, units, Show last refreshed, Update now. Tap
    the weather line on the home screen to refresh it on the spot (Wi-Fi is
    never turned on for you).
  - Plugin entries: Add or remove plugins (including "Resume current book"
    and File Manager), Edit entries (reorder, rename, folders — tap a folder
    to edit what's inside; folders are one level deep), Row spacing, Max
    entries per page (shows "Auto-fit to page" when uncapped), and Show page
    number. On the home screen, tapping a folder swaps the list for its
    contents, with a "←" row to return; long-pressing a section (Build Mode
    on) jumps straight to its settings.
- Wallpaper: enable, select image, fit (Fit / Fill / Stretch / Original size),
  lighten.
- Extras: Build Mode and Presets.
- The Settings menu also has Restart KOReader and Quit KOReader.
- Pull down from the top edge for KOReader's own top menu at any time. It also
  has Tools > ennUI, which opens the home screen.
- Optional: assign the action "ennUI: home screen" to a gesture.

## One-time tutorials
Two toasts, each shown once, ever:
- Right after your first setup, a reminder to swipe up for Settings.
- The first time you turn weather on, a reminder that tapping it refreshes it.

## About the file-browser flash
ennUI builds its screen the moment a book closes and reacts the instant
KOReader shows the file browser, when that signal is available, so the switch
back is close to instant on most setups. This is working within what a plugin
can do without changing how KOReader's own file browser gets shown, so it
isn't an absolute guarantee in every situation.

## Safety
- Errors while building or showing a screen leave the normal file browser in place.
- The loading splash (used only on the slower fallback path) closes itself
  after 5 seconds if nothing replaces it.
- If a start never finished drawing the home screen, the next start skips it once.
- To remove ennUI: delete the `ennui.koplugin` folder (and `settings/ennui.lua`).

## Known limits
- Very high outline thickness still means more paint work than none at all —
  it's linear in thickness, not free.
- White text will be invisible against the default blank background unless
  paired with an outline or a dark wallpaper.
- The outline/drop shadow effects won't apply to a character your font draws
  as a picture-style glyph rather than a plain shape.
