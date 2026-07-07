# One-off: seed tts_watcher_state.json with current line counts of every
# Cowork session JSONL on disk. Run once after upgrading to v4.4 so the
# watcher's first run doesn't replay any existing transcript.
import os
import json

sessions_dir = os.path.join(os.environ["APPDATA"], "Claude", "local-agent-mode-sessions")
state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_watcher_state.json")

scan_root = "\\\\?\\" + os.path.abspath(sessions_dir)
positions = {}
for root, dirs, files in os.walk(scan_root, followlinks=True):
    for fname in files:
        if fname.endswith(".jsonl") and fname != "audit.jsonl":
            fpath = os.path.join(root, fname)
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    n = sum(1 for _ in f)
                key = fpath
                if key.startswith("\\\\?\\"):
                    key = key[4:]
                positions[key] = n
            except Exception:
                pass

tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"positions": positions}, f)
os.replace(tmp, state_file)
print(f"Seeded {len(positions)} transcript position(s) into {state_file}")
for k, v in list(positions.items())[-3:]:
    print(f"  ...{k[-70:]} -> {v} lines")
