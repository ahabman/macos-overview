# Overview

Full-screen macOS dashboard showing Slack and Teams unread counts, the next calendar meeting, and the state of each Claude Code session.

## Build and run

```bash
./build.sh
open build/Overview.app
```

## Data sources

- **Slack, Teams**: Dock badge labels, read through the Accessibility API. Requires Accessibility permission (System Settings > Privacy & Security > Device Control and Data Access). No message content is read.
- **Slack conversations**: optional. `SlackLiveClient` receives message events over Slack Socket Mode and lists who wrote in DMs, group DMs, and channels where you were @-mentioned. The list clears when the Slack Dock badge clears. Message text is checked only for an @-mention and is never stored or shown. Setup is in "Slack app setup" below.
- **Next meeting**: EventKit, from calendars synced into macOS Calendar. The Outlook/Exchange account must be added in System Settings > Internet Accounts. Requires Calendar permission.
- **Claude sessions**: `hooks/session-status.py`, registered as a Claude Code hook in `~/.claude/settings.json` for SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, Notification, Stop, StopFailure and SessionEnd. It writes one file per session to `~/.claude/overview-sessions/` with the session ID, working directory, state and timestamp. Files not updated for 12 hours are ignored.

## Permissions after rebuild

The app has an ad-hoc signature. `build.sh` sets its designated requirement to the bundle identifier `com.bamfhealth.overview` instead of the default cdhash, so Accessibility and Calendar grants stay valid after a rebuild. Builds made before this change had cdhash requirements; remove their entries from the Accessibility list once and add the app again.

Diagnostic lines go to `~/Library/Logs/Overview.log`.

## Slack app setup

1. In the Slack app at https://api.slack.com/apps, open **Socket Mode** and enable it. Create the app-level token it offers with the `connections:write` scope and copy the `xapp-` token.
2. Open **Event Subscriptions**, enable events, and under **Subscribe to events on behalf of users** add `message.im`, `message.mpim`, `message.channels` and `message.groups`.
3. Open **OAuth & Permissions** and confirm the user token scopes include `channels:history`, `groups:history`, `im:history` and `mpim:history` (step 2 adds them). Reinstall the app to the workspace.
4. Store both tokens in the Keychain (each command prompts for the value; `-U` replaces an existing item):

```bash
security add-generic-password -U -s com.bamfhealth.overview.slack -a app-token -w
security add-generic-password -U -s com.bamfhealth.overview.slack -a token -w
```

5. Quit and reopen Overview. On first launch macOS asks whether Overview may read each Keychain item; choose **Always Allow**.

## App icon

`scripts/make-icon.swift` draws the icon from measurements of `Resources/icon-source.png` and writes `Resources/AppIcon.icns` (plus `Resources/AppIcon-1024.png` for preview). Rerun it after changing the drawing:

```bash
swift scripts/make-icon.swift
```
