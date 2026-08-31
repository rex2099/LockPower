# Design

LockPower is intentionally small. A user LaunchAgent starts one native menu bar
app at login. It is packaged as a standard `LockPower.app` with `LSUIElement`,
so macOS manages its status item without showing it in the Dock. The process
subscribes to public macOS workspace and distributed notifications for screen
lock, unlock, display sleep, and display wake events.

When the screen is locked or the display sleeps, LockPower starts one delayed
work item. Duplicate notifications do not restart the timer. If the user
returns before the delay expires, the work item is cancelled. Otherwise the
process enables Low Power Mode. Unlocking the screen cancels any pending work
and immediately disables Low Power Mode.

A native `NSStatusItem` presents the current state and manual controls. It does
not use a repeating timer: the icon changes on state transitions, and the
remaining delay is calculated only when the menu opens. Pausing automation is
session-local and restores full performance immediately.

The process never changes system sleep, display timeout, disk sleep, Wake for
network access, or remote-access settings. Low Power Mode is not system sleep,
so LockPower can reduce peak power and heat while keeping an always-on Mac
reachable.

## Failure behavior

- If LockPower crashes, launchd restarts it.
- At startup, an unlocked session is restored to full performance.
- If the privilege rule is missing, the command fails non-interactively and the
  error is written to the local log.
- Uninstalling restores full performance before removing the privilege rule.
