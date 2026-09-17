# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Omarchy 4.x bar-widget plugin (`vscarpenter.ha-lights`) that controls Home Assistant lights by area. It is three pieces and nothing else: `manifest.json` (plugin metadata, settings schema), two QML files loaded by `omarchy-shell` (Quickshell), and the `ha-lights` bash script. There is no build step, package manager, or test suite.

## Running and testing

- The script is the only thing that can be exercised outside the shell. Use demo mode to test without Home Assistant (state persists in `$XDG_RUNTIME_DIR/ha-lights-demo.json`; delete it to reset):
  ```bash
  ./ha-lights --demo status | jq
  ./ha-lights --demo toggle area:kitchen
  ./ha-lights --demo brightness light.desk_lamp 40
  ./ha-lights --url http://<ha-host>:8123 status | jq   # real HA, token from ~/.config/homeassistant/token
  ```
- The installed plugin lives at `~/.config/omarchy/plugins/vscarpenter.ha-lights`, which is a **separate git clone**, not a symlink to this repo. Changes here don't reach the running bar until copied/pulled there (`omarchy plugin update vscarpenter.ha-lights` after pushing).
- In the installed copy, `BarWidget.qml` edits hot-reload on save; `Panel.qml` edits require `omarchy restart shell`.
- Toggle demo mode in the live widget: `omarchy bar set vscarpenter.ha-lights demo On|Off`.

## Architecture

**Security boundary (keep it intact).** QML never touches the token or makes HTTP calls. Every Home Assistant request goes through `ha-lights`, which reads `tokenFile` per request and passes the `Authorization` header to curl via `-K <(...)` (a file descriptor), so the token is never in argv, env, QML state, or output. Don't add code paths that read the token in QML or pass it as an argument.

**`ha-lights` script.** Always prints one line of JSON — `{"error": ...}` with exit 1 on failure (via `fail()`), `{"ok":true}` for commands, or the status object. `status` POSTs a Jinja template (`STATUS_TEMPLATE`) to `/api/template` that walks `areas()` and collects light entities, then the `SUMMARIZE` jq program turns that into `{rooms: [{id, name, on, available, brightness, lights: [...]}], on: <bulbs on>}`. A light is a *group* if it has `is_hue_group` or an `entity_id` attribute; the group drives the room's brightness and is excluded from the bulb list. Brightness is converted 0–255 → 0–100. Sorting uses a natural-sort key. Targets are validated as `area:<id>` or `light.<id>`. Demo mode reuses `SUMMARIZE` on a seeded JSON file and `demo_apply` mimics a Hue bridge (group state follows bulbs).

**`BarWidget.qml`** is thin: a `BarIconButton` plus a `Loader` for `Panel.qml`, injecting `bar`/`settings`/`anchorItem`/`hostWidget` into it and forwarding the `opened`/`open`/`close`/`closeForPopoutSwitch` shape contract the shell expects (modeled on the built-in `omarchy.weather` widget). All state lives in the panel.

**`Panel.qml`** owns state and the optimistic-UI logic:
- Settings are read with `setting(key, default)` and turned into `baseCommand`; `connectionKey` (string-joined) resets all state when URL/token/demo change.
- `reported` = last status from HA; `rooms` = `overlay(reported)` with pending user clicks (`desired`) laid on top. Holds are keyed `area:<id>` or entity id and clear when HA reports the matching value (brightness within ±2) or after `holdMs` (8s). This exists because Hue reports new state seconds after a command.
- `actionSeq`/`statusSeq`: every command bumps `actionSeq`; a status read that started before the latest command is discarded and re-run, so an in-flight poll can't revert a click. Only one `statusProc` runs at a time (`refreshQueued`).
- Commands run via `Quickshell.execDetached`; afterwards `settleTimer` re-polls 4× at 1s. Brightness slider changes are debounced 250ms, and the model isn't replaced while the debounce is pending (a slider mid-drag would jump).
- Polling: every 5s while open, `refreshIntervalSec` while closed.
- UI uses Omarchy's own components (`KeyboardPanel`, `PanelHero`, `ToggleSwitch`, `PanelSlider`, `PanelActionButton`) from `qs.Ui`/`qs.Commons` so it follows the theme.

## Conventions

- Adding a setting means updating `manifest.json` in both `defaults` and `schema`, reading it in `Panel.qml` via `setting()`, and documenting it in the README settings table.
- Releases: bump `version` in `manifest.json` and add a dated `CHANGELOG.md` entry (commit message `Release x.y.z`).
