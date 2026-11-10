#!/usr/bin/python3 -I
"""Claude Code hook: records each session's state for the Overview app.

Writes ~/.claude/overview-sessions/<session_id>.json on every hook event and
deletes the file on SessionEnd. Records no prompt or tool-input text.
Always exits 0 and prints nothing, so it never blocks or alters a session.
"""
import json
import os
import re
import subprocess
import sys
import time

STATUS_DIR = os.path.expanduser("~/.claude/overview-sessions")

# hook_event_name -> state shown by Overview
STATES = {
    "SessionStart": "idle",
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "PermissionRequest": "waiting",
    "Stop": "idle",
    "StopFailure": "error",
}


def host_app_path():
    """Bundle path of the outermost .app among this hook's ancestor processes,
    e.g. /Applications/Claude.app or /System/Applications/Utilities/Terminal.app.
    Overview activates that app when the session row is clicked."""
    found = ""
    pid = os.getppid()
    for _ in range(40):
        if pid <= 1:
            break
        try:
            out = subprocess.run(["/bin/ps", "-o", "ppid=,comm=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
            ppid, comm = out.split(None, 1)
        except Exception:
            break
        marker = comm.find(".app/")
        if marker != -1:
            found = comm[:marker + 4]
        pid = int(ppid)
    return found


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    session_id = str(data.get("session_id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]+", session_id):
        return
    event = data.get("hook_event_name", "")
    path = os.path.join(STATUS_DIR, session_id + ".json")

    if event == "SessionEnd":
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        return

    if event == "Notification":
        # permission_prompt and idle_prompt both mean the session waits on the user
        state = "waiting"
    else:
        state = STATES.get(event)
    if state is None:
        return

    app_path = ""
    try:
        with open(path) as f:
            app_path = json.load(f).get("app_path", "")
    except Exception:
        pass
    if not app_path:
        app_path = host_app_path()

    record = {
        "session_id": session_id,
        "cwd": data.get("cwd", ""),
        "state": state,
        "event": event,
        "updated": time.time(),
        "app_path": app_path,
        "transcript_path": data.get("transcript_path", ""),
    }
    os.makedirs(STATUS_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(record, f)
    os.replace(tmp, path)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
