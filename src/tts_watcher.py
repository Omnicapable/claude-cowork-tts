# -*- coding: utf-8 -*-
# tts_watcher.py v4.14 - Automatic TTS for Claude Cowork sessions.
# Monitors the Cowork session transcript (JSONL) and speaks assistant messages.
# Also monitors tts_queue.txt for special commands (voice previews, etc.)
# Regular CLI sessions are handled by the Stop hook (tts_hook.ps1) instead.
#
# Double-speaking fix: Claude no longer writes to tts_queue.txt for regular
# responses — the queue file is reserved for special commands only.
#
# v4.14: Per-system voice/speed. Every utterance is tagged "SYS=cowork|" so the
#        server can apply the voice and speed chosen for Cowork in the panel.
#        This watcher stores NO settings of its own - they live server-side in
#        ~/.claude/tts_systems.json - so nothing here needs reloading when you
#        change a setting, and a watcher restart cannot lose one.
#        Requires tts_server v3.4+; older servers ignore the tag and fall back to
#        the global voice, so a mixed install still speaks.
# v4.12: Panel status endpoint on 127.0.0.1:59011 (GET /state, POST /replay) so the
#        Omnicapable Voice panel can show a Cowork chip and replay this system.
# v4.11: Age filter field fix — the v4.8 filter read a "ts" field that does not
#        exist in Claude transcripts (they use ISO-8601 "timestamp"), so it never
#        ran. Now reads "timestamp" (parsed via datetime.fromisoformat); numeric
#        "ts" still accepted as a fallback.
# v4.10: Per-request voice prefix — set WATCHER_VOICE = "voice_name" to have this
#        watcher use a specific voice for every message it sends. The server receives
#        "VOICE=name|text" and speaks with that voice without changing its global default.
# v4.9: Single-instance lock — on startup the watcher binds a UDP socket to
#        127.0.0.1:59002. If a second copy starts (e.g. the watchdog and the
#        restart bat fire simultaneously), it cannot bind the port and exits
#        immediately. The OS releases the binding on process exit, even on a
#        crash, so no stale lock files.
# v4.8: Message age filter — lines whose timestamp is older than
#        MESSAGE_MAX_AGE_SECONDS (180 s) are silently skipped. Prevents the
#        watcher from replaying old messages when it switches to a session file
#        that was recently touched but already contains old content.
# v4.7: Log rotation — tts_watcher_log.txt capped at 1 MB; on overflow it is
#        renamed to .prev and a fresh log starts (same pattern as watchdog/Kokoro).
# v4.6: POLL reduced from 0.5s to 0.1s — cuts worst-case detection latency from
#        500ms to 100ms; overhead is negligible (local file size check each poll).
# v4.5: Kokoro retry cooldown (skips messages during server outage instead of
#        hammering), should_skip_text() filters JSON permission payloads, and
#        SCAN_INTERVAL reduced from 30s to 10s for faster new-session detection.
# v4.4 replay fix: per-transcript line positions are persisted to
# tts_watcher_state.json, so re-opening an existing session (which bumps its
# mtime and used to trigger the FRESH_WINDOW heuristic) no longer replays the
# entire transcript. The fresh/stale heuristic now only fires for files we
# have never spoken from before.
#
# Run once at login via start_tts_watcher.bat

import ctypes
import glob
import json
import os
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

# --- Config ---
# Where Cowork keeps its session transcripts. Windows uses %APPDATA%; macOS uses
# ~/Library/Application Support. Before v4.14 this fell back to a literal Windows
# path ("~\AppData\Roaming"), so on macOS the watcher scanned a directory that can
# never exist and silently never spoke. TTS_SESSIONS_DIR overrides both.
def _default_sessions_dir():
    override = os.environ.get("TTS_SESSIONS_DIR")
    if override:
        return override
    if sys.platform == "darwin":
        base = os.path.join(os.path.expanduser("~"), "Library", "Application Support")
    elif os.name == "nt":
        base = os.environ.get("APPDATA") or os.path.join(
            os.path.expanduser("~"), "AppData", "Roaming")
    else:                                  # Linux / other: XDG convention
        base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
            os.path.expanduser("~"), ".config")
    return os.path.join(base, "Claude", "local-agent-mode-sessions")

SESSIONS_DIR   = _default_sessions_dir()
QUEUE_FILE     = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_queue.txt")
TOGGLE_FILE    = os.path.join(os.environ.get("USERPROFILE", os.path.expanduser("~")), ".claude", "tts_enabled.txt")
PREVIEW_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview_voices.py")
PREVIEW_HELPER = os.path.join(os.environ.get("USERPROFILE", os.path.expanduser("~")), ".claude", "kokoro", "tts_preview.py")
LOG_FILE       = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_watcher_log.txt")
STATE_FILE     = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts_watcher_state.json")
STATE_MAX      = 500   # cap persisted positions; prunes oldest entries beyond this
STATE_MAX_AGE_DAYS = 7  # prune state entries for transcripts older than this
HOST, PORT     = "127.0.0.1", 59001
POLL             = 0.1        # seconds between checks
SCAN_INTERVAL    = 5          # seconds between full directory scans (expensive \\?\ walk)
KOKORO_RETRY_SECONDS = 15     # cooldown after a failed Kokoro send
LOG_ROTATE_BYTES = 1_048_576  # rotate log at 1 MB
MESSAGE_MAX_AGE_SECONDS = 180 # skip messages whose timestamp is older than this
SYSTEM_NAME    = "cowork"     # v4.14: identifies this system to the server
# Defined up here (not beside the status server below) because send_to_kokoro
# uses it, and the hotkey thread can call that before the bottom of the file has
# executed.
_CONTROL_PREFIXES = ("__STOP__", "__REPLAY__", "__PREVIEW", "__SET_", "__GET_", "__SPEAK__")
# Legacy per-watcher voice. Since v4.14 this is only a FALLBACK: if you pick a
# Cowork voice in the panel, the panel wins and this is ignored. Left in place so
# existing hand-edited installs keep working untouched.
WATCHER_VOICE = None          # set to e.g. "af_bella" to use a per-watcher voice
FRESH_WINDOW   = 60    # if a newly-detected file was modified within this many seconds,
                       # treat it as a fresh user session and speak from the start
                       # instead of skipping existing lines
ENABLE_HOTKEY  = os.environ.get("TTS_ENABLE_GLOBAL_HOTKEY", "").lower() in {"1", "true", "yes", "on"}

# --- Single-instance lock ---
# Bind a UDP socket to a fixed port. Only one process can hold the binding;
# any duplicate exits immediately. The OS releases the binding on process
# exit, even on a crash — no stale files needed.
_lock_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    _lock_socket.bind(("127.0.0.1", 59002))
except OSError:
    print("tts_watcher: another instance is already running — exiting.")
    sys.exit(0)

# --- State ---
current_jsonl      = None
current_line_count = 0
last_queue_mtime   = 0
last_scan_time     = 0
known_positions    = {}   # jsonl_path -> line_count we've already spoken through
kokoro_retry_after = 0    # epoch time before which Kokoro sends are skipped

# --- Logging ---
def log(msg):
    line = f"{time.strftime('[%Y-%m-%d %H:%M:%S]')} {msg}"
    print(line)
    try:
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) >= LOG_ROTATE_BYTES:
            prev = LOG_FILE + ".prev"
            if os.path.exists(prev):
                os.remove(prev)
            os.rename(LOG_FILE, prev)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# --- Persistent transcript positions ---
def _normalize_path(p):
    r"""Strip Windows \\?\ long-path prefix so the same file always maps to the
    same dict key regardless of which scan produced the path."""
    if p and p.startswith("\\\\?\\"):
        return p[4:]
    return p

def load_state():
    global known_positions
    try:
        if not os.path.exists(STATE_FILE):
            return
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        raw = data.get("positions", {})
        # Normalize keys and drop entries whose transcript no longer exists.
        cleaned = {}
        for p, n in raw.items():
            if not isinstance(n, int):
                continue
            key = _normalize_path(p)
            if os.path.exists(key) or os.path.exists("\\\\?\\" + key):
                cleaned[key] = n
        known_positions = cleaned
        log(f"Loaded state: {len(known_positions)} known transcript(s)")
    except Exception as e:
        log(f"Could not load state ({e}); starting empty")
        known_positions = {}

def save_state():
    try:
        positions = known_positions
        # Prune entries for transcripts older than STATE_MAX_AGE_DAYS.
        cutoff = time.time() - STATE_MAX_AGE_DAYS * 86400
        positions = {
            p: n for p, n in positions.items()
            if os.path.exists(p) and os.path.getmtime(p) >= cutoff
        }
        # Also cap by count: if we still exceed STATE_MAX, drop oldest by mtime.
        if len(positions) > STATE_MAX:
            ranked = sorted(
                positions.items(),
                key=lambda kv: os.path.getmtime(kv[0]) if os.path.exists(kv[0]) else 0,
                reverse=True,
            )
            positions = dict(ranked[:STATE_MAX])
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"positions": positions}, f)
        os.replace(tmp, STATE_FILE)
    except Exception as e:
        log(f"Could not save state: {e}")

def remember_position(path, line_count):
    known_positions[_normalize_path(path)] = line_count
    save_state()

def lookup_position(path):
    return known_positions.get(_normalize_path(path))

# --- Helpers ---
def is_enabled():
    try:
        with open(TOGGLE_FILE, "r") as f:
            return f.read().strip().lower() == "on"
    except Exception:
        return True

def send_to_kokoro(text):
    global kokoro_retry_after
    now = time.time()
    if now < kokoro_retry_after:
        log(f"Kokoro unavailable; skipped {len(text)} chars (cooldown)")
        return
    payload = f"VOICE={WATCHER_VOICE}|{text}" if WATCHER_VOICE else text
    # v4.14: tag real speech with this system so the server can apply the voice
    # and speed chosen for Cowork. Control commands (__STOP__ and friends) are
    # NOT tagged - they are instructions, not utterances.
    if not text.startswith(_CONTROL_PREFIXES):
        payload = f"SYS={SYSTEM_NAME}|{payload}"
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(payload.encode("utf-8"))
        log(f"Spoke {len(text)} chars")
        _remember_spoken(text)
        kokoro_retry_after = 0
    except Exception as e:
        log(f"ERROR sending to Kokoro: {e}")
        kokoro_retry_after = time.time() + KOKORO_RETRY_SECONDS

def run_preview(args):
    if not os.path.exists(PREVIEW_SCRIPT):
        log(f"Legacy preview script missing ({PREVIEW_SCRIPT}); install tts_preview.py to enable previews.")
        return
    try:
        subprocess.Popen([sys.executable, PREVIEW_SCRIPT] + args)
        log(f"Preview launched: {args}")
    except Exception as e:
        log(f"ERROR launching preview: {e}")


def run_preview_command(text):
    """Route legacy preview tokens and friendly phrases through the installed helper.

    Returns True when the queue text was a preview command or malformed preview
    command, False when it is not a preview command.
    """
    # Legacy fallback keeps old installs usable if the installed helper is missing.
    if not os.path.exists(PREVIEW_HELPER):
        if text == "__PREVIEW_QUICK__":
            run_preview(["--category"])
            return True
        if text == "__PREVIEW_ALL__":
            run_preview([])
            return True
        if text.startswith("__PREVIEW_VOICE__:"):
            run_preview([text.split(":", 1)[1].strip()])
            return True
        return False

    try:
        check = subprocess.run(
            [sys.executable, PREVIEW_HELPER, "--dry-run", text],
            capture_output=True,
            text=True,
            timeout=5,
        )
        detail = (check.stdout or check.stderr or "").strip()
        if check.returncode == 0:
            kwargs = {}
            if os.name == "nt":
                kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            subprocess.Popen([sys.executable, PREVIEW_HELPER, text], **kwargs)
            log(f"Preview command: {text[:60]} -> {detail}")
            return True
        if check.returncode == 1:
            log(f"Invalid preview command: {text[:60]} -> {detail}")
            return True
        return False
    except Exception as e:
        log(f"Preview helper error: {e}")
        return True

# --- JSONL transcript monitoring (Cowork sessions) ---
_jsonl_scan_logged = False

def find_latest_jsonl():
    global _jsonl_scan_logged
    best_file, best_mtime, count = None, 0, 0
    walk_errors = []
    # Use \\?\ prefix to bypass Windows 260-char MAX_PATH limit
    # (session JSONL paths can be 380+ chars)
    scan_root = SESSIONS_DIR
    if sys.platform == "win32" and not scan_root.startswith("\\\\"):
        scan_root = "\\\\?\\" + os.path.abspath(scan_root)
    def onerror(e):
        walk_errors.append(str(e))
    try:
        for root, dirs, files in os.walk(scan_root, followlinks=True, onerror=onerror):
            for fname in files:
                if fname.endswith(".jsonl") and fname != "audit.jsonl":
                    fpath = os.path.join(root, fname)
                    try:
                        mtime = os.path.getmtime(fpath)
                        count += 1
                        if mtime > best_mtime:
                            best_mtime = mtime
                            best_file = fpath
                    except Exception:
                        pass
    except Exception as e:
        log(f"ERROR in find_latest_jsonl: {e}")
    if not _jsonl_scan_logged:
        if walk_errors:
            log(f"Walk errors (first 2): {walk_errors[:2]}")
        log(f"Scan: found {count} jsonl(s), best=...{best_file and best_file[-60:] or 'None'}")
        _jsonl_scan_logged = True
    return best_file

_METADATA_KEYS = {"outcome", "risk_level", "user_authorization", "rationale"}

def should_skip_text(text):
    """Return True if text is a JSON permission-check payload (never speak these)."""
    try:
        data = json.loads(text)
    except Exception:
        return False
    return isinstance(data, dict) and bool(_METADATA_KEYS.intersection(data.keys()))

def extract_text_from_line(line):
    """Return spoken text if this JSONL line is a complete assistant response, else None."""
    try:
        data = json.loads(line.strip())
        if data.get("type") != "assistant":
            return None
        msg = data.get("message", {})
        if msg.get("stop_reason") != "end_turn":
            return None
        # Age filter: skip messages older than MESSAGE_MAX_AGE_SECONDS.
        # Prevents replaying old content when the watcher switches to a session
        # file that was recently touched but already contains old messages.
        # Transcript lines carry an ISO-8601 "timestamp" (e.g.
        # "2026-06-25T02:04:18.591Z"); older formats used a numeric epoch "ts".
        # Accept either so the filter never silently no-ops.
        msg_time = None
        raw_ts = data.get("ts")
        if raw_ts is not None:
            try:
                msg_time = float(raw_ts)
                if msg_time > 1e10:   # milliseconds -> seconds
                    msg_time /= 1000
            except (ValueError, TypeError):
                msg_time = None
        if msg_time is None:
            raw_iso = data.get("timestamp")
            if raw_iso:
                try:
                    iso = raw_iso.replace("Z", "+00:00")
                    msg_time = datetime.fromisoformat(iso).timestamp()
                except (ValueError, TypeError, AttributeError):
                    msg_time = None
        if msg_time is not None and (time.time() - msg_time) > MESSAGE_MAX_AGE_SECONDS:
            return None
        texts = [
            block["text"]
            for block in msg.get("content", [])
            if block.get("type") == "text" and block.get("text", "").strip()
        ]
        if not texts:
            return None
        joined = " ".join(texts)
        return None if should_skip_text(joined) else joined
    except Exception:
        return None

def check_jsonl():
    global current_jsonl, current_line_count, last_scan_time

    # Only run the expensive directory scan on startup or every SCAN_INTERVAL seconds.
    # Between scans, go straight to reading the current file.
    now = time.time()
    if current_jsonl is None or (now - last_scan_time) >= SCAN_INTERVAL:
        latest = find_latest_jsonl()
        last_scan_time = now
        if not latest:
            return
        if latest != current_jsonl:
            # New session detected. Decision order:
            #   1. If we've spoken from this transcript before (persisted state),
            #      resume from the saved line — this is what prevents replays when
            #      an existing session's mtime gets bumped (the v4.3 bug).
            #   2. Otherwise, if the file was modified very recently, treat it as
            #      a fresh user session and read from the start so we don't miss
            #      the first assistant response (Haiku can complete a reply between
            #      scans).
            #   3. Otherwise (stale file found on watcher startup), skip to end.
            current_jsonl = latest
            _jsonl_scan_logged = False  # reset so new session scan details get logged
            try:
                with open(current_jsonl, "r", encoding="utf-8", errors="ignore") as f:
                    total_lines = sum(1 for _ in f)
            except Exception as e:
                log(f"Error reading new JSONL: {e}")
                return

            saved = lookup_position(current_jsonl)
            if saved is not None:
                # Cap at total_lines in case the file was rotated/truncated.
                current_line_count = min(saved, total_lines)
                log(f"Resuming known session at line {current_line_count}/{total_lines}: ...{current_jsonl[-60:]}")
            else:
                try:
                    file_mtime = os.path.getmtime(current_jsonl)
                except Exception:
                    file_mtime = 0
                if (now - file_mtime) <= FRESH_WINDOW:
                    current_line_count = 0
                    log(f"Tracking new session (fresh, reading from start): ...{current_jsonl[-60:]}")
                else:
                    current_line_count = total_lines
                    log(f"Tracking new session (stale, skipping to end): ...{current_jsonl[-60:]}")
                remember_position(current_jsonl, current_line_count)
            return

    if not current_jsonl:
        return

    try:
        with open(current_jsonl, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        return

    new_lines = lines[current_line_count:]
    if not new_lines:
        return

    current_line_count = len(lines)
    remember_position(current_jsonl, current_line_count)

    for line in new_lines:
        text = extract_text_from_line(line)
        if text and is_enabled():
            log(f"Speaking: {text[:80]}...")
            send_to_kokoro(text)

# --- Queue file monitoring (special commands only) ---
def check_queue():
    global last_queue_mtime
    try:
        if not os.path.exists(QUEUE_FILE):
            return
        mtime = os.path.getmtime(QUEUE_FILE)
        if mtime == last_queue_mtime:
            return
        last_queue_mtime = mtime
        with open(QUEUE_FILE, "r", encoding="utf-8") as f:
            text = f.read().strip()
        if not text:
            return
        # Clear queue
        with open(QUEUE_FILE, "w", encoding="utf-8") as f:
            f.write("")
        last_queue_mtime = os.path.getmtime(QUEUE_FILE)

        log(f"Queue command: {text[:60]}")
        if not run_preview_command(text):
            log(f"Ignored non-preview queue text: {text[:60]}")
    except Exception as e:
        log(f"Queue error: {e}")

# --- Ctrl+Alt+X hotkey via polling (50ms interval, ~50ms response) ---
def _hotkey_poller():
    # ctypes.windll exists only on Windows; on macOS the hotkey is owned by the
    # hotkey daemon (tts_hotkey_mac.py), so this poller must not run at all.
    # Without this guard, setting TTS_ENABLE_GLOBAL_HOTKEY=1 on a Mac throws in
    # a background thread. Matches the guard codex_tts_watcher.py already has.
    if sys.platform != "win32":
        log("Hotkey poller is Windows-only; skipped on this platform.")
        return
    VK_CONTROL = 0x11
    VK_MENU    = 0x12   # Alt
    VK_X       = 0x58
    user32     = ctypes.windll.user32
    user32.GetAsyncKeyState.restype = ctypes.c_short
    was_pressed = False
    log("Ctrl+Alt+X hotkey poller started (50ms response)")
    while True:
        ctrl    = user32.GetAsyncKeyState(VK_CONTROL) & 0x8000
        alt     = user32.GetAsyncKeyState(VK_MENU)    & 0x8000
        x       = user32.GetAsyncKeyState(VK_X)       & 0x8000
        pressed = bool(ctrl and alt and x)
        if pressed and not was_pressed:
            threading.Thread(target=send_to_kokoro, args=("__STOP__",), daemon=True).start()
            log("Hotkey Ctrl+Alt+X: speech stopped")
        was_pressed = pressed
        time.sleep(0.05)

if ENABLE_HOTKEY:
    threading.Thread(target=_hotkey_poller, daemon=True).start()
else:
    log("Ctrl+Alt+X hotkey poller disabled. Set TTS_ENABLE_GLOBAL_HOTKEY=1 to enable it.")


# --- Panel status endpoint (loopback only) ----------------------------------
# The Omnicapable Voice panel (127.0.0.1:59010) polls this to decide whether to
# show a chip for this system, and to route Replay at it. Bound to
# 127.0.0.1 only, so it is unreachable from the network. If the port is already
# taken the watcher logs it and carries on — status is a convenience, never a
# reason to stop speaking.
STATUS_PORT     = 59011
WATCHER_VERSION = "4.14"
# SYSTEM_NAME and _CONTROL_PREFIXES are defined in the config block at the top.

_last_spoken = {"text": ""}          # last real utterance, for panel replay


def _remember_spoken(text):
    """Record the last genuine utterance so the panel can replay it.

    Control commands and voice-prefixed payloads are not speech, so they must
    not overwrite what Replay would say."""
    try:
        body = text.split("|", 1)[1] if text.startswith("VOICE=") else text
        if body and not body.startswith(_CONTROL_PREFIXES):
            _last_spoken["text"] = body
    except Exception:
        pass


def _status_payload():
    return {
        "system":    SYSTEM_NAME,
        "version":   WATCHER_VERSION,
        "mode":      None,
        "last_text": _last_spoken["text"][:400],
        "enabled":   is_enabled(),
    }


def _start_status_server():
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        def _cors(self):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")

        def _json(self, obj, code=200):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code); self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            try:
                n = int(self.headers.get("Content-Length") or 0)
                return json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                return {}

        def do_OPTIONS(self):
            self.send_response(204); self._cors(); self.end_headers()

        def do_GET(self):
            if self.path.split("?")[0] in ("/state", "/"):
                self._json(_status_payload())
            else:
                self._json({"error": "not found"}, 404)

        def do_POST(self):
            path = self.path.split("?")[0]
            if path == "/replay":
                text = _last_spoken["text"]
                if not text:
                    self._json({"ok": False, "error": "nothing spoken yet"}, 409); return
                threading.Thread(target=send_to_kokoro, args=(text,), daemon=True).start()
                self._json({"ok": True})
            else:
                self._json({"error": "not found"}, 404)

        def log_message(self, *a):        # keep the watcher log readable
            pass

    try:
        srv = ThreadingHTTPServer(("127.0.0.1", STATUS_PORT), Handler)
    except OSError as e:
        log(f"Panel status endpoint unavailable on {STATUS_PORT}: {e}")
        return
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    log(f"Panel status endpoint listening on 127.0.0.1:{STATUS_PORT}")

_start_status_server()

# --- Main loop ---
log("tts_watcher v4.14 started. Monitoring Cowork transcript + queue commands.")
load_state()

while True:
    try:
        check_jsonl()
        check_queue()
    except Exception as e:
        log(f"Loop error: {e}")
    time.sleep(POLL)

