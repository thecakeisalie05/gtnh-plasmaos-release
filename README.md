# GTNH PlasmaOS

GTNH PlasmaOS is a Lua 5.2-compatible graphical OpenComputers environment for GT New Horizons. Its color-driven desktop uses the GPU's native text resolution with window chrome, mouse interaction, responsive applications, and live GTNH dashboards. It isolates applications and services, supports independent local/Terminal Server sessions, and installs or updates through immutable staged versions.

Version `0.1.0-alpha` has passed the host simulation suite. It has not been certified on a live GTNH computer; see [hardware validation](docs/hardware-compatibility.md) and [known limitations](docs/known-limitations.md) before treating it as a stable release.

## Requirements

- Minecraft 1.7.10 with GTNH OpenComputers/OpenOS and Lua 5.2 `bit32` support.
- At least 192 KiB RAM for installation; Compact Desktop is recommended below Tier 3.
- A writable filesystem.
- A GPU/screen for the graphical profile. Headless recovery remains available.
- Internet Card for online installation only. Installed operation is offline-first.

No component address is compiled in. Screens, keyboards, GPUs, modems, and GTNH integrations are discovered at runtime.

## Desktop controls

- `F1`: launcher
- `F2`: Terminal
- `F3`: File Explorer
- `F4`: System Monitor
- `Alt+Tab`: cycle windows
- `F12`: render/input diagnostics overlay
- Click title-bar controls to minimize, maximize/restore, or close. Drag title bars and the lower-right cell to move/resize.

The launcher includes Settings, editor, Component Explorer, Application Center, automation, and adapter-backed Energy, inventory/fluid, redstone, AE/ME, GregTech, reactor, base, rack, robot, and navigation centers. Unsupported hardware is shown as unavailable rather than guessed.

## Build and publish

Run the test suite with a Lua 5.2-compatible interpreter:

```text
lua tests/run.lua
```

Build release artifacts after choosing the stable public directory that will contain `manifest.txt` and the versioned files:

```text
python tools/build_release.py --base-url https://example.invalid/plasmaos/0.1.0
```

Upload the contents of `dist/release/` to that base URL and upload `dist/installer.lua` as `<base-url>/installer.lua`. Then upload `dist/bootstrap.lua` to Pastebin as an unlisted paste, note the returned ID, and rebuild metadata with:

```text
python tools/build_release.py --base-url https://example.invalid/plasmaos/0.1.0 --pastebin-id <ID>
```

The resulting user command is exactly:

```text
pastebin run <ID>
```

The repository cannot supply the real ID or hosting URL until someone publishes those external artifacts. Do not publish a bootstrap whose placeholders remain.

## Offline install

Copy the built offline archive to a mounted OpenComputers filesystem, extract it, place `dist/installer.lua` alongside it, then run:

```text
lua installer.lua --offline /mnt/<disk>/<release-directory>
```

The installer preserves `/home`, backs up a pre-existing `/init.lua`, verifies every SHA-256 and size, stages under `/system/versions`, validates the boot entry, renames the completed version into place, and changes the activation pointer atomically.

## Recovery

Hold either Shift key during boot for Normal, Safe mode, Recovery shell, or Previous version. Three failed boot attempts prefer the last-known-good version in safe mode. The emergency shell needs no graphical service or network. See [recovery](docs/recovery.md).

## Source map

- `src/kernel`: scheduler, event/IPC, supervision primitives, logging, capabilities
- `src/display`: endpoint/session registry, compositor, damage, input
- `src/services`: config, apps, files, packages, telemetry, alarms, network, users, memory
- `src/ui`, `src/apps`, `src/shell`: desktop and bundled applications
- `src/integrations`: runtime-discovered adapter framework
- `installer`, `recovery`, `tools`: transactional delivery and recovery
- `tests`: deterministic host simulation

Architecture and operational limits are documented in `docs/`.
