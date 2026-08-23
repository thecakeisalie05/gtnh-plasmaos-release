# Remote terminals

Terminal Server virtual screens and keyboards are ordinary explicit endpoints. The OS never relies on OpenOS's changing primary screen/keyboard.

Connection flow:

1. Component discovery finds a screen and calls its documented `getKeyboards()` method.
2. The endpoint registry creates or reconnects the stable endpoint ID.
3. The generation increments and the session broker restores only that endpoint's session.
4. Stale queued input/render work is discarded.
5. The compositor explicitly leases a GPU, binds the endpoint's screen, verifies geometry, and requests complete damage.

Disconnect removes the address mappings, clears endpoint render work, increments generation, and marks only the owning session disconnected. Scheduler, automation, networking, and other sessions continue.

Bounds: 128 raw events, 48 normalized input events per session, 12 damage fragments, one pending frame, one executing frame, 32 GPU operations per display slice. Drag/scroll are coalesced. Default terminal FPS is 6 and unknown screens conservatively use 5.

The System Monitor Sessions/Performance views and `F12` overlay expose session, screen, generation, resolution, queue depths, endpoint state, and render errors. The watchdog classifies scheduler-healthy pending damage as a display stall and raw-without-normalized input as routing trouble. `restart-session <id>` rebuilds only that session.

If a modded client forwards Remote Terminal keyboard events but drops mouse events,
press `F9` for the session-local software pointer. Arrow keys move it, Enter or Space
clicks, Page Up/Page Down scrolls, and Escape returns the keyboard to applications.
This fallback does not replace or disable normal OpenComputers touch input.

The automated suite covers 50 reconnects, two-session routing, a 1,000-event drag flood, stale frame rejection, and GPU error containment. The live RT-01–RT-10 matrix remains mandatory in [hardware compatibility](hardware-compatibility.md).
