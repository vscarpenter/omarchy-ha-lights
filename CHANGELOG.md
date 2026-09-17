# Changelog

## 0.1.1 — 2026-09-16

### Fixed

- The arrow next to a room now expands it to show its bulbs. Clicking it did
  nothing in 0.1.0.

### Changed

- Rooms and bulbs are sorted by name, with numbers in numeric order
  ("Light 2" before "Light 10").
- Bulb rows are indented under their room and slightly dimmer.

## 0.1.0 — 2026-09-16

First release.

- Bar widget with a panel listing Home Assistant areas that contain lights
- Room and per-bulb on/off switches and brightness sliders
- All on and all off buttons; right-click the bar icon for all off
- Clicks held on screen until Home Assistant confirms the new state
- Settings for URL, token file, refresh interval, and demo mode
- `ha-lights` command-line script
