# Known limitations — 0.1.0-alpha

These are explicit alpha boundaries, not silently weakened tests.

1. **Live GTNH validation is unavailable in this workspace.** The deterministic host suite passes, but no attached Minecraft/OpenComputers machine exists to run the blocking in-game matrix. Reproduce by installing the candidate on the target pack and follow `hardware-compatibility.md`.
2. **The public bootstrap is not published.** `dist/bootstrap.lua` in a local development build can only contain the base URL supplied to the release tool. Resume by hosting `dist/release`, hosting `dist/installer.lua`, uploading the rebuilt bootstrap to Pastebin, then testing `pastebin run <ID>` from a blank disk.
3. **Terminal Server endpoint kind is conservative unless configured.** OpenComputers exposes screen/keyboard identity but no portable promise that labels a screen as physical versus Terminal Server. Unknown screens still receive independent sessions and remote-safe 5 FPS behavior. Record the observed component snapshot before adding a pack-specific classifier.
4. **GTNH machine APIs require observed adapters.** Component Explorer and the generic adapter kit are complete; AE/ME, GregTech, reactor, inventory/fluid, and addon centers remain explicitly unavailable until method names and return types are captured from the exact pack. This avoids dangerous fabricated control APIs.
5. **Cooperative Lua cannot forcibly preempt a coroutine that never yields.** First-party work is chunked and watchdog-accounted, but a malicious native-tight loop can consume the VM until OpenComputers' own execution limit intervenes. App crash isolation applies once control returns/errors; safe boot remains the recovery path.
6. **Some rich desktop features are intentionally compact in the alpha.** The editor provides atomic save, cursor editing, bounded undo, and file launch, but not a full multi-buffer IDE. Application Center exposes the transactional package service but does not yet provide repository browsing. File Explorer's recursive copy is background/cancellable; filename search has an explicit scan cap.

Stable versioning must not remove this file until the associated validation or feature is complete and evidenced.
