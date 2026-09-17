# Changelog

## 0.2.0 — 2026-09-16

### Added

- Lights that aren't assigned to an area appear in an "Other" room at the
  bottom of the list instead of being hidden.
- Keybinding and script control over IPC: `omarchy-shell vscarpenter.ha-lights
  toggle|allOn|allOff|roomOn|roomOff|roomToggle|scene|refresh`.
- Scenes assigned to an area show as buttons when the room is expanded.
- A color temperature slider for rooms and bulbs that support it.
- `ha-lights` gains `temp` and `scene` commands, and accepts a comma-separated
  list of light entities as a target.

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
