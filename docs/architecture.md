# Architecture

## Failure-domain layering

The stable stage-1 loader selects an immutable version. That version creates the runtime core, supervised services, display/session services, desktop/app platform, then integration adapters. An app never receives raw `component`, GPU, or signal access.

The cooperative scheduler tracks PID, parent, owner, app/session, state, CPU slice estimate, work count, resources, windows, cleanup callbacks, and bounded mailbox. It offers yield, sleep, event wait, IPC receive, and cancellation. Lua cannot preempt a coroutine that never yields; the runtime therefore measures returned slice duration, reports offenders, protects an emergency boot path, and keeps all first-party work chunked.

One event broker consumes `computer.pullSignal`. It republishes bounded events to the scheduler, hardware service, and input broker. Subscriber exceptions are contained.

The supervisor applies never/on-failure/always policy, a restart window, maximum restart count, and exponential backoff. Noncritical failure degrades one service instead of rebooting.

## Display and session invariants

`DisplayEndpoint` stores an explicit screen, GPU, keyboard set, kind, geometry, connection state, target FPS, generation, damage/frame state, errors, and heartbeats. `Session` stores independent user, focus, clipboard, windows, theme, notifications, lock state, and input queue.

Only `display/compositor.lua` binds GPUs or emits draw calls. A render batch captures the endpoint generation. Reconnect, keyboard reassignment, GPU change, resolution recovery, or session restart increments it; stale work is dropped. A GPU shared by endpoints is rebound and lease-validated before every resumed command batch, preventing partial-frame work from continuing on the wrong screen.

Each endpoint has one damage accumulator and at most one pending plus one executing frame. Regions merge and collapse to a bounded full frame. Frames are paced per endpoint and execute a bounded number of GPU operations per scheduler step.

Input is mapped by the signal's explicit screen/keyboard address. Each session queue is bounded; drag and scroll floods coalesce while key/click ordering is preserved. Lock and global shortcuts intercept before window delivery. Application handling runs in the application's scheduler coroutine, not inside the raw input callback.

## Persistence and security

Structured configs use strict JSON, schema versions, exact one-step migrations, `.new` validation, backup, then rename. Important package and activation databases use the same transaction primitive. Logs, telemetry, crash reports, dedupe sets, notifications, mailboxes, and queues are capped.

Capabilities distinguish component read from control. Control adapters require an explicit declaration, optional confirmation/interlock, authorization, rate control, and audit entry. Secrets store salted iterative verifiers rather than plaintext and never enter normal settings/logs.

## Performance profiles

Remote/unknown screens default to solid backgrounds, no animation, and 5–6 FPS; local defaults to 12 FPS. Only damage triggers drawing. File copy, telemetry, network, packages, integrations, automation, and logging run in separate bounded service slices. Warning/critical memory states trim telemetry, lower optional load, and reject nonessential app launches while preserving Terminal and System Monitor.
