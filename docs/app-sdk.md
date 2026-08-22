# App and integration SDK

Register an app with `apps:register(manifest, factory)`. The manifest provides `id`, `name`, category, essential flag, and minimum/default geometry. The factory receives `{api, session, options, services}` and returns a model with `render()`, optional `onEvent(event)`, optional `tick()`, and optional `refreshInterval`.

`render()` returns an array of ASCII-safe lines. The app manager caches those lines. Input is sent through the process mailbox; application code never runs in the raw input or compositor callback. An exception crashes the PID, removes its windows/resources, records a bounded report, and raises a notification without affecting the session.

Use service facades for files, config, notifications, IPC, network, telemetry, packages, components, and automation. Never require `component` in an app.

An integration adapter declares `id`, `detect(componentSnapshot)`, `pollInterval`, `poll(address, broker, snapshot)`, and optional actions. Snapshots contain runtime type/address/method names. Do not guess method names: inspect them in Component Explorer, record the target pack version, and create configuration with `integrations.generic_adapter.fromConfig`.

Poll results map metric IDs to `{value, unit, quality}`. Quality must be `live`, `stale`, `error`, or `unavailable`. Control actions may declare `confirm` and `interlock`; the manager additionally requires `component.control` and audits execution. Adapter errors stay attributed to the adapter/component.
