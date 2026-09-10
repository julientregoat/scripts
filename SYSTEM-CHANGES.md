# System changes

A log of deliberate, persistent changes made to macOS system state —
things that live outside any repo and would otherwise be invisible: LaunchAgents and
LaunchDaemons, `defaults write` tweaks, disabled login items, kernel/network settings.

**Why this file exists.** These changes are easy to make and easy to forget. Worse, some of
them get silently reverted — an app update reinstalls the LaunchAgent you disabled — and the
symptom comes back months later looking like a brand-new problem. Every entry below records
how to verify it is still in effect, so drift is detectable instead of mysterious.

Run [`verify_system_changes.sh`](./verify_system_changes.sh) to check every entry at once.

## Scope — this repo is public

Entries here must be safe to share. That is the point: most of these are fixes worth handing
to someone hitting the same problem.

Keep out of this file anything that describes security posture rather than a fix — disabled
protections, VPN or network topology, firewall rules, anything tied to a specific machine's
identity. Individually those look as harmless as everything else here; together they are a
map. They belong in the private dotfiles repo, or nowhere.

## Format

Each entry records: what changed, why, the exact commands, how to verify, and how to undo.
Newest first. Note which machine(s) it was applied to — these are not synced automatically.

---

## 2026-09-07 — Disable Logitech G HUB autostart

**Applied to:** one of two MacBooks. **Still outstanding on the other**, which has the same
G HUB install and the same bug.

**What changed:** renamed `/Library/LaunchAgents/com.logi.ghub.plist` to `.disabled` and booted
the service out, so Logitech G HUB no longer starts at login.

**Why:** `lghub_system_tray` wedges into a runaway LaunchServices retry loop — it asks to launch
the G HUB app roughly once a second, the request resolves to `LAUNCH: Asking CSUI to launch 0 items`,
never succeeds, and retries forever. Each attempt activates the G HUB agent app and steals
frontmost, making the machine effectively unusable. Observed 732 attempts in one 12-hour login
session, escalating from isolated hourly checks into a continuous ~1/sec loop. Diagnosed
2026-07-07, recurred 2026-09-07 (a reboot only buys one session).

Nothing user-triggered causes it — not mouse use, not Bluetooth activity.

**Commands:**

```sh
# sudo cannot prompt from a non-TTY context; this uses the native macOS auth dialog
osascript -e 'do shell script "/bin/launchctl bootout gui/501/com.logi.ghub || true; \
  /bin/mv /Library/LaunchAgents/com.logi.ghub.plist \
  /Library/LaunchAgents/com.logi.ghub.plist.disabled" with administrator privileges'
```

**Verify:** `com.logi.ghub` absent from `launchctl list`, and `com.logi.ghub.plist` absent from
`/Library/LaunchAgents/` (only the `.disabled` variant present).

**Undo:** rename `.disabled` back and reboot, or just open `/Applications/lghub.app` — the app
still works on demand for RGB and profile changes.

**Impact:** none on mouse or keyboard function. macOS handles the HID input natively and
per-device config is stored onboard. What is lost is background profile switching and RGB
control while the app is closed.

**Regression risk — this one can undo itself.** `/Library/LaunchDaemons/com.logi.ghub.updater.plist`
(root, `lghub_updater`) was deliberately left running; it is not the offender. But a G HUB
auto-update may reinstall the LaunchAgent. The tell-tale is `com.logi.ghub.plist` reappearing
without the `.disabled` suffix.

**If it comes back before you can re-disable it:** `killall lghub_agent lghub_system_tray` restores
focus immediately for the current session. (`lghub_updater` is root-owned and survives the
`killall`; that is fine, it is harmless.)

**Diagnosing a suspected focus-steal:**

```sh
# 1. Is something pinning frontmost? Poll for ~25s; a healthy machine shows your actual app.
while :; do lsappinfo front | xargs -I{} lsappinfo info -only name {}; sleep 1; done

# 2. Confirm the retry loop (use the absolute path — zsh shadows `log` and chokes on OR predicates)
/usr/bin/log show --last 40m --style compact \
  --predicate 'eventMessage CONTAINS "launchViaCSUA"'
```
