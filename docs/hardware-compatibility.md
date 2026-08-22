# Hardware compatibility and validation

## Assumptions recorded

The source targets OpenComputers/OpenOS on Minecraft 1.7.10 with Lua 5.2-compatible syntax and `bit32`. The current GTNH pack version and component inventory were not available in this workspace. Recent GTNH reports show OpenComputers GTNH builds in the 1.11.x line, but runtime discovery is authoritative.

Documented signal identity used by the router:

- `key_down`, `key_up`, and `clipboard`: keyboard address
- `touch`, `drag`, `drop`, `scroll`, and `screen_resize`: screen address
- screen `getKeyboards()`: associated keyboard addresses
- `component_added`/`component_removed` and OpenOS availability signals: hotplug discovery

Terminal Server screen/keyboard associations are refreshed on availability
changes and once more when an unknown input address is first observed. Remote
Terminal mouse and keyboard events are OpenComputers checked signals: on an
owned machine, the Minecraft player must appear in `computer.users()`.

References: GTNewHorizons/OpenComputers, MightyPirates/OpenComputers `master-MC1.7.10`, and the OpenComputers Signals documentation.

## Minimum matrix

| Profile | Expected hardware | Policy |
|---|---|---|
| Tier 1 / Compact | Tier 1 GPU/screen, small RAM | Geometry clamps to GPU; small layouts; low histories/FPS |
| Tier 2 / Compact | Tier 2 GPU/screen | Normal apps in compact layout; 5–10 FPS |
| Tier 3 / Full | Tier 3 GPU/screen, larger RAM/disk | Multi-window desktop; 12 FPS local default |
| Terminal Server | Virtual screen/keyboard plus explicit GPU | Independent session; 6 FPS; coalesced damage/input |
| Headless | No screen/GPU | Boot/recovery and background services; graphical session when endpoint appears |
| Offline | No Internet Card | Installed OS works; installer accepts offline release directory |

## Manual release gate (not yet executed)

Run on the exact target GTNH pack and record pack/OC versions, CPU/RAM, GPU/screen tier, Terminal Server tier, filesystem, keyboards per screen, and component snapshot.

- A01–A06: blank install, interruption, checksum rejection, resumable setup, safe mode, rollback.
- B01–D05: desktop/window/small-screen/theme, file operations and cancellable copy, editor atomic save, app/runaway/service isolation.
- RT-01–RT-10: 50 live reconnects, range loss, drag flood, telemetry load, foreground crash, component churn, GPU error, soak, pressure, diagnostics.
- E11–E13: simultaneous local/remote input independence, automation continuity, one-session reset.
- F01–J04: hotplug/screen loss/no Internet/low memory, package/update/offline, modem timeout/dedupe/auth, optional-integration absence/discovery/stale/alarm/control, migrations/corruption/log/telemetry caps.

Stable release is blocked until this matrix passes. Resume with `lua tests/run.lua`, build a candidate, install it on the target machine, and fill an evidence log alongside this file.
