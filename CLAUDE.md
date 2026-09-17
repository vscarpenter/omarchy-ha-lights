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
  ./ha-lights --demo temp area:office 5000
  ./ha-lights --demo scene scene.kitchen_dinner
  ./ha-lights --url https://<ha-host>:8123 status | jq   # real HA, token from ~/.config/homeassistant/token
  ```
  The demo file reseeds itself when it predates the fields the current version reads.
- The installed plugin lives at `~/.config/omarchy/plugins/vscarpenter.ha-lights`, which is a **separate git clone**, not a symlink to this repo. Changes here don't reach the running bar until copied/pulled there (`omarchy plugin update vscarpenter.ha-lights` after pushing).
- In the installed copy, `BarWidget.qml` edits hot-reload on save; `Panel.qml` edits require `omarchy restart shell`.
- Toggle demo mode in the live widget: `omarchy bar set vscarpenter.ha-lights demo On|Off`.

## Architecture

**Security boundary (keep it intact).** QML never touches the token or makes HTTP calls. Every Home Assistant request goes through `ha-lights`, which reads `tokenFile` per request and passes the `Authorization` header to curl via `-K <(...)` (a file descriptor), so the token is never in argv, env, QML state, or output. Don't add code paths that read the token in QML or pass it as an argument. The token only travels over TLS: `preflight` runs `check_url` before the token file is touched, accepting `https://` or plain `http://` to a literal loopback address (`127.x.x.x`, `[::1]`; not `localhost`), and curl is pinned to that one scheme with `--proto` and never follows redirects. `--ca-file` (the `caFile` setting) maps to `--cacert`; never add `-k`. Every authenticated request goes through `api()`, which caps the response at `MAX_RESPONSE_BYTES` (curl `--max-filesize` plus a `head -c` backstop) before anything is parsed; `api_fail` maps its exit codes to messages. These came out of the marketplace security review, so don't loosen them.

**`ha-lights` script.** Always prints one line of JSON — `{"error": ...}` with exit 1 on failure (via `fail()`), `{"ok":true}` for commands, or the status object. `status` POSTs a Jinja template (`STATUS_TEMPLATE`) to `/api/template` that walks `areas()` plus a trailing `none` for lights in no area, collecting light and scene entities, then the `SUMMARIZE` jq program turns that into `{rooms: [{id, name, virtual, on, available, brightness, hasTemp, temp, tempMin, tempMax, scenes: [{id, name}], lights: [...]}], on: <bulbs on>}`. The no-area room has id `_unassigned`, `virtual: true`, and sorts last; the panel targets its bulbs as a comma-separated list because there is no area to address. A light is a *group* if it has `is_hue_group` or an `entity_id` attribute; the group drives the room's brightness and color temperature and is excluded from the bulb list. Brightness is converted 0–255 → 0–100; temperature is kelvin from `color_temp_kelvin`, with `hasTemp` from `supported_color_modes`. Sorting uses a natural-sort key. Targets are validated as `area:<id>`, `light.<id>`, or `light.a,light.b`; scenes as `scene.<id>`. `ha_call <domain> <service> <body>` wraps service calls. Demo mode reuses `SUMMARIZE` on a seeded JSON file and `demo_apply` mimics a Hue bridge (group state follows bulbs); demo scenes carry a brightness and temp that `demo_apply` applies to the room.

**`BarWidget.qml`** is thin: a `BarIconButton` plus a `Loader` for `Panel.qml`, injecting `bar`/`settings`/`anchorItem`/`hostWidget` into it and forwarding the `opened`/`open`/`close`/`closeForPopoutSwitch` shape contract the shell expects (modeled on the built-in `omarchy.weather` widget). All state lives in the panel.

**`Panel.qml`** owns state and the optimistic-UI logic:
- Settings are read with `setting(key, default)` and turned into `baseCommand`; `connectionKey` (string-joined) resets all state when URL/token/demo change.
- `reported` = last status from HA; `rooms` = `overlay(reported)` with pending user clicks (`desired`) laid on top. Holds are keyed `area:<id>` or entity id and clear when HA reports the matching value (brightness within ±2, temperature within `tempToleranceK`) or after `holdMs` (8s). This exists because Hue reports new state seconds after a command. Slider holds merge into an existing hold; on/off clicks replace it. `roomKey(room)` is the hold key and `roomTarget(room)` the script target (they differ for the virtual "Other" room).
- `actionSeq`/`statusSeq`: every command bumps `actionSeq`; a status read that started before the latest command is discarded and re-run, so an in-flight poll can't revert a click. Only one `statusProc` runs at a time (`refreshQueued`).
- Commands run via `Quickshell.execDetached`; afterwards `settleTimer` re-polls 4× at 1s. Brightness and temperature slider changes are debounced 250ms each, and the model isn't replaced while either debounce is pending (`sliderPending`; a slider mid-drag would jump). Scene clicks run without a hold and rely on the settle polls.
- An `IpcHandler` on target `vscarpenter.ha-lights` exposes open/close/toggle plus `allOn`, `allOff`, `roomOn`, `roomOff`, `roomToggle`, `scene`, `refresh` for `omarchy-shell` and Hyprland bindings. The base `Panel` handler is disabled (`manageIpc: false`) so this one owns the target.
- `TempSlider` is an inline component (icon, warm-to-cool `PanelSlider`, kelvin label) used for rooms and bulbs with `hasTemp`.
- Polling: every 5s while open, `refreshIntervalSec` while closed.
- UI uses Omarchy's own components (`KeyboardPanel`, `PanelHero`, `ToggleSwitch`, `PanelSlider`, `PanelActionButton`, `Button` for scene chips) from `qs.Ui`/`qs.Commons` so it follows the theme.

## Conventions

- Adding a setting means updating `manifest.json` in both `defaults` and `schema`, reading it in `Panel.qml` via `setting()`, and documenting it in the README settings table.
- Releases: bump `version` in `manifest.json` and add a dated `CHANGELOG.md` entry (commit message `Release x.y.z`).
