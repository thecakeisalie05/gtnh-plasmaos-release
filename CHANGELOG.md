# Changelog

## OpenComputers Remote Terminal touch host fix

- Identified the GTNH OpenComputers 1.12.44+ rack-distance check that discards
  Remote Terminal pointer packets before Lua receives them.
- Added a pairing-key-scoped OpenComputers patch covering touch, drag, drop,
  scroll, clipboard, file drop, and analyzer input without weakening physical
  screen or unpaired-terminal checks.
- Built and tested an exact-version 1.12.48 replacement JAR for GTNH 2.9.b2.

## 0.1.0-alpha — 2026-08-22

- Added transactional installer, immutable version activation, boot-attempt recovery, safe shell, and last-known-good selection.
- Added cooperative scheduler, event/IPC brokers, bounded service supervision, capabilities, atomic configuration, structured rotating logs, users, automation, networking, packages, telemetry, alarms, and memory degradation.
- Added explicit display endpoints, generation-checked frames, compositor-only GPU ownership, dirty-region rendering, bounded/coalesced per-session input, endpoint recovery, and watchdog diagnostics.
- Added responsive desktop, panel, launcher, window management, themes, Terminal, File Explorer, System Monitor, Settings, editor, Component Explorer, Application Center, automation UI, and adapter-driven GTNH centers.
- Rebuilt the desktop around color-driven window chrome, responsive application views, mouse/keyboard selection, styled toolbars and status areas, native-resolution layouts, and actionable empty states across all 20 bundled applications.
- Refined visual hierarchy with higher-contrast themes, bordered window surfaces, larger labeled title controls, segmented clickable toolbar buttons, and interactive taskbar tiles.
- Added per-session working directories with `cd`, `pwd`, and relative path handling throughout the Command Console.
- Added cooperative native `wget`, `pastebin get`, and `pastebin run` commands, including in-place bootstrap and repair support.
- Added host simulations for scheduling, crashes, service failure, atomic writes, config migrations, remote reconnects, input floods, stale frames, GPU errors, telemetry, alarms, network authorization, and packages.

This alpha still requires the documented in-game hardware validation gate before a stable release.
