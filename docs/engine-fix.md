# Phase 1 — Engine-Level AccessKit Fix (Context Only)

This repository is an **addon** (GDScript) that runs on top of the official Godot 4.7 Stable
Editor/runtime — it does not vendor or modify Godot's engine source. However, Phase 1 of this
project involved a small, prior fix inside Godot's own C++ engine (in a team member's fork), and
understanding it is necessary context for how the Native Accessibility Bridge in this addon works.
This page documents that fix without redistributing Godot's engine source.

## Where

`drivers/accesskit/accessibility_server_accesskit.cpp`, inside
`AccessibilityServerAccessKit::update_if_active()`.

## The problem

Godot's accessibility system periodically calls `update_if_active()` to push any pending
accessibility-tree changes to the OS. On Android, that requires a JNI reference to the "host" (the
Java View that hosts accessibility) to actually deliver the update. During early app startup there
is a brief window where the accessibility subsystem is already ticking but the Android host hasn't
finished being created yet. The original code called the dispatch function unconditionally,
dereferencing a null/uninitialized host and crashing the app with a SIGSEGV on startup.

## The fix

A defensive null-check was added around the Android-specific dispatch path:

```cpp
void AccessibilityServerAccessKit::update_if_active(const Callable &p_callable) {
    ...
#ifdef ANDROID_ENABLED
    if (window.value.host != nullptr) {          // <-- defensive check added
        accesskit_android_queued_events *events =
            accesskit_android_adapter_update_if_active(...);
        if (events) {
            accesskit_android_queued_events_raise(events, get_jni_env(), window.value.host);
        }
    }
#endif
    ...
}
```

## Why this approach

- **A guard clause, not a lock**: this is a lifecycle-ordering issue (the host object simply
  doesn't exist yet), not a concurrent-access race in the classic multi-threading sense. A mutex
  would add overhead for no benefit; a null-check is the minimal correct fix at the exact point the
  crash occurred.
- **Fixed at the call site, not upstream**: forcing the host to exist earlier would mean
  restructuring Android's own Activity/View lifecycle — much higher risk than one defensive check
  where the null dereference actually happens.
- **Android-only, by design**: only Android's path needs a JNI "host" object at all — the same
  function has separate `#ifdef` blocks for Windows, macOS, and Linux, each using their own AccessKit
  adapter with no equivalent host object.

## Why this matters for the addon in this repository

Every accessibility feature this addon relies on — its invisible per-room `Button` overlay, focus
synchronization, activation — depends on Godot successfully dispatching accessibility tree updates
to Android without crashing at startup. This fix is what makes that dispatch path safe to rely on;
the addon itself adds no new engine-level code and depends entirely on stock Godot 4.7 behavior
once this fix (or an engine version that already contains an equivalent fix) is present.
