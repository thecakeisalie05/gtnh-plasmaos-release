# Recovery

The stable `/init.lua` loader is separate from versioned userland. It reads `/system/active`, `/system/last-good`, and `/system/boot-attempts`.

- Hold Shift during the 0.35-second boot window for the menu.
- Safe mode and Recovery open a deterministic text shell with graphical/network services disabled.
- After three incomplete boots, the loader prefers last-known-good in safe mode.
- Successful service startup resets attempts and promotes the active version to last-known-good.

Recovery commands list versions, select a version, browse/read files, inspect logs, reboot, and shut down. Selecting a version only updates the small activation pointer; version files are immutable.

The installer saves the prior root loader as `/init.lua.pre-plasmaos`. `recovery/uninstall.lua` restores it without deleting `/home`, PlasmaOS versions, or configuration. Removal of preserved data is deliberately manual.

If an install is interrupted before activation, delete nothing: rerun the bootstrap. A `.staging-*` directory is never boot-selected. A checksum failure removes only that staging directory. A failed pointer write restores its backup. Use `--repair` to stage a distinct repaired version rather than overwriting running core files.
