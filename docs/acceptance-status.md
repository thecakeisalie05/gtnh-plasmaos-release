# Acceptance status — 0.1.0-alpha

## Automated host gate: pass

`lua tests/run.lua` currently reports 27 passed, 0 failed. Coverage includes bounded/coalesced queues, strict persistence encoding, SHA-256, damage merging, fair sleep/yield behavior, app crash isolation, bounded supervision, subscriber isolation, application mailbox ownership, independent local/remote routing, a 1,000-event drag flood, 50 remote reconnect cycles without duplicate sessions, generation-stale frame rejection, GPU fault containment, shared-GPU lease rebinding, atomic rollback, config migration backup, bounded/stale telemetry, alarm debounce, network auth/dedupe, package abort/commit/remove, chunked file copy, log rotation, first-run resume, staged core update, activation, and rollback.

All Lua files also pass a parse-only syntax scan.

## External/manual gate: blocked by missing target and publication

The workspace has no GTNH game instance, OpenComputers computer, Terminal Server, component inventory, public release host, or Pastebin ID. Therefore A01/A02/A04–A06, visual B/C checks, live D02 behavior, RT-01–RT-10, E11–E13, hardware F checks, online G/H behavior, observed GTNH I adapters, and long-duration J caps are not claimed as passed.

Evidence needed to unblock:

1. Publish a candidate using `docs/packaging.md`.
2. Record exact GTNH/OpenComputers versions and `components` output.
3. Execute the matrix in `docs/hardware-compatibility.md` on Tier 1/2/3, headless, local plus Terminal Server, offline, and memory-pressure profiles.
4. Save logs/screenshots and any adapter snapshots next to the matrix.
5. Fix failures without weakening the host suite, rebuild, and repeat `pastebin run <ID>` from a blank disk.
