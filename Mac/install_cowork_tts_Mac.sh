#!/bin/bash
# =============================================================================
# install_cowork_tts_Mac.sh  v1.0
# One-shot installer for Claude Cowork TTS (Kokoro ONNX) — macOS
# Installs the Kokoro TTS server AND the Cowork session watcher.
# Fully offline after install. No API keys. No data sent to third parties.
#
# Requirements: macOS 12+, Python 3.9+, Claude Desktop (Cowork) installed
# Usage: chmod +x install_cowork_tts_Mac.sh && ./install_cowork_tts_Mac.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="$HOME/.claude"
KOKORO_DIR="$CLAUDE_DIR/kokoro"
PORT=59001
PLIST_LABEL="com.user.kokoro-tts-server"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
WATCHER_PLIST_LABEL="com.user.cowork-tts-watcher"
WATCHER_PLIST_PATH="$HOME/Library/LaunchAgents/$WATCHER_PLIST_LABEL.plist"
COWORK_DIR="$HOME/Documents/Claude Cowork TTS"
VERSION="1.0"

echo ""
echo "============================================"
echo " Claude Cowork TTS Installer v$VERSION — Mac"
echo "============================================"
echo ""

# --- 1. Check Python ---------------------------------------------------------
echo "[1/11] Checking Python..."
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: python3 not found.${NC}"
  echo "Install Python 3.9+ from https://python.org or via Homebrew: brew install python"
  exit 1
fi
PYTHON=$(command -v python3)
echo "      Found: $($PYTHON --version) at $PYTHON"

# --- 2. Install Python packages ----------------------------------------------
echo "[2/11] Installing Python packages..."
if ! $PYTHON -m pip install kokoro-onnx sounddevice numpy --quiet 2>/dev/null; then
    # Homebrew / system Python marks itself "externally managed" (PEP 668) and
    # refuses a global pip install. Retry the way pip's own error recommends.
    echo "      System Python is externally managed (PEP 668); retrying with --break-system-packages..."
    $PYTHON -m pip install kokoro-onnx sounddevice numpy --quiet --break-system-packages
fi
echo "      Done."

# --- 3. Create folders -------------------------------------------------------
echo "[3/11] Creating folders..."
mkdir -p "$KOKORO_DIR"
echo "      Done."

# --- 4. Download model files -------------------------------------------------
echo "[4/11] Downloading Kokoro model files (~336 MB total)..."
BASE_URL="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
for FILE in "kokoro-v1.0.onnx" "voices-v1.0.bin"; do
  DEST="$KOKORO_DIR/$FILE"
  if [ -f "$DEST" ]; then
    echo "      Already exists: $FILE"
  else
    echo "      Downloading $FILE..."
    curl -L --progress-bar "$BASE_URL/$FILE" -o "$DEST"
    echo "      Done: $FILE"
  fi
done

# --- 5. Write Python scripts -------------------------------------------------
echo "[5/11] Writing Python scripts..."

cat > "$KOKORO_DIR/tts_server.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
tts_server.py v2.3 - Persistent Kokoro TTS server.
Loads the model once, listens on localhost:59001 for text to speak.
Pipelined: synthesizes sentence-by-sentence so first sentence plays immediately.
Supports: stop, replay, speed change, voice change, voice memory, pronunciation
          cleanup, per-request voice prefix (VOICE=name|text), output-device
          follow, auto-restart watchdog.
v2.3: Cents fix - the ' point ' rule now runs AFTER the money rule, so "$3.50"
      reads "3 dollars and 50 cents" again rather than "3 dollars point 50".
      Header corrected to match shipped behaviour. Consolidates the replay
      lineage (__REPLAY__, output-device follow, emoji strip, money/decimal
      parsing) with the voice-memory + pronunciation work. Single source of truth.
v2.2: Voice memory (saves chosen voice to voice.txt; reloads on restart).
      Pronunciation: version numbers read as "point", bare domains as "dot".
v2.1: Per-request voice prefix -- VOICE=name|text overrides global voice for
      that request only. Zero race conditions; global voice unchanged.
v2.0: Initial pipelined release with sentence splitting and speed/voice controls.
"""
import socket, threading, queue, os, re, time
import numpy as np
import sounddevice as sd

HOST, PORT = "127.0.0.1", 59001
VOICE, SPEED, LANG, MAX_CHARS = "am_onyx", 1.2, "en-us", 5000
VOICE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice.txt")
def _load_voice():
    try:
        with open(VOICE_FILE, "r", encoding="utf-8") as f:
            v = f.read().strip()
            if v:
                return v
    except Exception:
        pass
    return "am_onyx"
def _save_voice(v):
    try:
        with open(VOICE_FILE, "w", encoding="utf-8") as f:
            f.write(v)
    except Exception:
        pass
VOICE = _load_voice()

base = os.path.dirname(os.path.abspath(__file__))
from kokoro_onnx import Kokoro
kokoro = Kokoro(os.path.join(base, "kokoro-v1.0.onnx"), os.path.join(base, "voices-v1.0.bin"))

# Pre-warm audio device so first sentence has no driver init delay
sd.play(np.zeros(1, dtype=np.float32), samplerate=24000)
sd.wait()

_speak_lock = threading.Semaphore(1)
_stop_event  = threading.Event()
_last_text  = ""      # last text spoken, for __REPLAY__
_last_voice = None

_last_utterance_ts = 0.0
def _refresh_audio_device():
    # Follow output-device switches (AirPods/headphones/Bluetooth) WITHOUT tearing
    # down PortAudio on every utterance — that was fragile (macOS PaMacCore -50).
    # Only re-scan devices after an idle gap (between bursts, not mid-burst), so a
    # rapid run of replies doesn't thrash the audio backend.
    global _last_utterance_ts
    now = time.time()
    idle = now - _last_utterance_ts
    _last_utterance_ts = now
    if idle > 8.0:
        try:
            sd._terminate(); sd._initialize()
        except Exception:
            pass

def clean_text(text):
    # --- Tables --- replace markdown tables with a brief label
    text = re.sub(r'(?m)(\|[^\n]+\|\n?)+', ' attached table. ', text)
    # --- Markdown removal ---
    text = re.sub(r'```[\s\S]*?```', '', text)
    text = re.sub(r'`[^`]+`', '', text)
    text = re.sub(r'(?m)^#{1,6}\s+', '', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
    text = re.sub(r'(?m)^\s*[-*+]\s+', '', text)
    text = re.sub(r'(?m)^\s*\d+\.\s+', '', text)
    text = re.sub(r'(?m)^\s*>\s+', '', text)
    text = re.sub(r'\n{2,}', '. ', text)
    text = re.sub(r'\n', ' ', text)
    # --- Symbols ---
    text = re.sub(r'[→←↑↓⇒⇐]', '', text)
    text = text.replace('\u2012', ',').replace('\u2013', ',').replace('\u2014', ',').replace('\u2015', ',').replace('\u2212', ',')
    text = re.sub(r'[|\\]', '', text)
    text = re.sub(r'[•·●◦]', '', text)
    # --- Emojis ---
    text = re.sub(r'[\U0001F000-\U0001FFFF\U00002600-\U000027BF\U0000FE00-\U0000FE0F]+', '', text)
    # --- URLs ---
    text = re.sub(r'https?://\S+', 'link', text)
    # --- Abbreviations ---
    text = re.sub(r'\be\.g\.\b', 'for example', text)
    text = re.sub(r'\bi\.e\.\b', 'that is', text)
    text = re.sub(r'\bvs\.\b', 'versus', text)
    text = re.sub(r'\betc\.\b', 'etcetera', text)
    text = re.sub(r'\bapprox\.\b', 'approximately', text)
    # --- Numbers ---
    text = re.sub(r'(?<=\d),(?=\d{3}(?:\D|$))', '', text)
    text = re.sub(r'\$(\d+)(?:\.(\d{2})(?!\d))?', lambda m: (m.group(1)+' dollars and '+m.group(2)+' cents') if m.group(2) else (m.group(1)+' dollars'), text)
    text = re.sub(r'(\d)%', r'\1 percent', text)
    text = re.sub(r'(\d+)x\b', r'\1 times', text)
    # --- Versions & bare domains ---
    # Must stay BELOW the money rule: this ' point ' substitution would otherwise
    # consume the decimal in "$3.50" and produce "3 dollars point 50".
    text = re.sub(r'(?<=\d)\.(?=\d)', ' point ', text)
    _TLDS = r'com|net|org|edu|gov|io|ai|app|dev|co|us|uk|ca|xyz|info|biz|me|tv|gg|so|sh'
    text = re.sub(r'(?<=[A-Za-z0-9])\.(?=(?:' + _TLDS + r')\b)', ' dot ', text, flags=re.IGNORECASE)
    # --- Whitespace cleanup ---
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()

def split_sentences(text):
    parts = re.split(r'(?<=[.!?])\s+', text)
    result = []
    for s in parts:
        s = s.strip()
        if not s: continue
        if result and len(result[-1]) < 40:
            result[-1] += ' ' + s
        else:
            result.append(s)
    return result if result else [text]

def synthesize(sentence, voice_override=None):
    v = voice_override if voice_override else VOICE
    samples, rate = kokoro.create(sentence, voice=v, speed=SPEED, lang=LANG)
    return np.array(samples, dtype=np.float32), rate

def speak(text, voice_override=None):
    text = clean_text(text)
    if not text: return
    if len(text) > MAX_CHARS: text = text[:MAX_CHARS] + " ... response truncated."
    sentences = split_sentences(text)
    _stop_event.clear()
    wav_queue = queue.Queue()

    def producer():
        for sentence in sentences:
            if _stop_event.is_set(): break
            try: wav_queue.put(synthesize(sentence, voice_override=voice_override))
            except Exception: pass
        wav_queue.put(None)

    threading.Thread(target=producer, daemon=True).start()
    _refresh_audio_device()

    while True:
        item = wav_queue.get()
        if item is None or _stop_event.is_set():
            while True:
                try: wav_queue.get_nowait()
                except queue.Empty: break
            break
        samples, rate = item
        sd.play(samples, samplerate=rate)
        sd.wait()
        if _stop_event.is_set():
            sd.stop()
            break

def handle_client(conn):
    global _last_text, _last_voice
    with conn:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk: break
            data += chunk
        text = data.decode("utf-8", errors="ignore").strip()

        if text == "__STOP__":
            _stop_event.set(); sd.stop(); return

        if text.startswith("__SPEED:") and text.endswith("__"):
            global SPEED
            try: SPEED = float(text[8:-2].strip())
            except ValueError: pass
            return

        if text == "__GETSPEED__":
            try: conn.sendall(str(SPEED).encode("utf-8")); conn.shutdown(socket.SHUT_WR)
            except Exception: pass
            return

        if text.startswith("__VOICE:") and text.endswith("__"):
            global VOICE
            VOICE = text[8:-2].strip(); _save_voice(VOICE); return

        if text == "__GETVOICE__":
            try: conn.sendall(VOICE.encode("utf-8")); conn.shutdown(socket.SHUT_WR)
            except Exception: pass
            return

        if text == "__REPLAY__":
            if _last_text:
                with _speak_lock: speak(_last_text, voice_override=_last_voice)
            return
        if text:
            # Per-request voice prefix: "VOICE=af_sky|actual text"
            req_voice = None
            if text.startswith("VOICE=") and "|" in text:
                prefix, text = text.split("|", 1)
                req_voice = prefix[6:].strip()
            if text:
                _last_text, _last_voice = text, req_voice
                with _speak_lock: speak(text, voice_override=req_voice)

def run_server():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT)); srv.listen()
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=handle_client, args=(conn,), daemon=True).start()

# Auto-restart watchdog
while True:
    try: run_server()
    except Exception: time.sleep(3)
PYEOF

cat > "$KOKORO_DIR/tts_speak.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""Direct synthesis fallback — used when server is not yet running."""
import sys, os, re
import numpy as np
import sounddevice as sd

VOICE, SPEED, LANG, MAX_CHARS = "am_onyx", 1.2, "en-us", 5000
VOICE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice.txt")
def _load_voice():
    try:
        with open(VOICE_FILE, "r", encoding="utf-8") as f:
            v = f.read().strip()
            if v:
                return v
    except Exception:
        pass
    return "am_onyx"
def _save_voice(v):
    try:
        with open(VOICE_FILE, "w", encoding="utf-8") as f:
            f.write(v)
    except Exception:
        pass
VOICE = _load_voice()
base = os.path.dirname(os.path.abspath(__file__))

def clean_text(text):
    # --- Tables ---
    text = re.sub(r'(?m)(\|[^\n]+\|\n?)+', ' attached table. ', text)
    # --- Markdown removal ---
    text = re.sub(r'```[\s\S]*?```', '', text)
    text = re.sub(r'`[^`]+`', '', text)
    text = re.sub(r'(?m)^#{1,6}\s+', '', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
    text = re.sub(r'(?m)^\s*[-*+]\s+', '', text)
    text = re.sub(r'(?m)^\s*\d+\.\s+', '', text)
    text = re.sub(r'(?m)^\s*>\s+', '', text)
    text = re.sub(r'\n{2,}', '. ', text)
    text = re.sub(r'\n', ' ', text)
    # --- Symbols ---
    text = re.sub(r'[→←↑↓⇒⇐]', '', text)
    text = text.replace('\u2012', ',').replace('\u2013', ',').replace('\u2014', ',').replace('\u2015', ',').replace('\u2212', ',')
    text = re.sub(r'[|\\]', '', text)
    text = re.sub(r'[•·●◦]', '', text)
    # --- URLs ---
    text = re.sub(r'https?://\S+', 'link', text)
    # --- Abbreviations ---
    text = re.sub(r'\be\.g\.\b', 'for example', text)
    text = re.sub(r'\bi\.e\.\b', 'that is', text)
    text = re.sub(r'\bvs\.\b', 'versus', text)
    text = re.sub(r'\betc\.\b', 'etcetera', text)
    text = re.sub(r'\bapprox\.\b', 'approximately', text)
    # --- Numbers ---
    text = re.sub(r'(?<=\d),(?=\d{3}(?:\D|$))', '', text)
    text = re.sub(r'\$(\d+)(?:\.(\d{2})(?!\d))?', lambda m: (m.group(1)+' dollars and '+m.group(2)+' cents') if m.group(2) else (m.group(1)+' dollars'), text)
    text = re.sub(r'(\d)%', r'\1 percent', text)
    text = re.sub(r'(\d+)x\b', r'\1 times', text)
    # --- Whitespace ---
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()

text = sys.stdin.read().strip()
if not text: sys.exit(0)
text = clean_text(text)
if len(text) > MAX_CHARS: text = text[:MAX_CHARS] + " ... response truncated."

from kokoro_onnx import Kokoro
kokoro = Kokoro(os.path.join(base,"kokoro-v1.0.onnx"), os.path.join(base,"voices-v1.0.bin"))
samples, rate = kokoro.create(text, voice=VOICE, speed=SPEED, lang=LANG)
sd.play(np.array(samples, dtype=np.float32), samplerate=rate)
sd.wait()
PYEOF

cat > "$KOKORO_DIR/set_voice.py" << 'PYEOF'
"""
set_voice.py - Change the TTS voice on the fly without restarting the server.
Usage: python3 set_voice.py VOICENAME
       python3 set_voice.py --current
"""
import sys, socket

PORT = 59001
VOICES = [
    "am_onyx","am_adam","am_echo","am_eric","am_fenrir","am_liam","am_michael","am_santa",
    "af_alloy","af_aoede","af_bella","af_heart","af_jessica","af_kore","af_nicole","af_nova","af_river","af_sarah","af_sky",
    "bf_alice","bf_emma","bf_isabella","bf_lily",
    "bm_daniel","bm_fable","bm_george","bm_lewis",
]

def send(msg, expect_reply=False):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", PORT))
    s.sendall(msg.encode("utf-8"))
    s.shutdown(socket.SHUT_WR)
    if expect_reply:
        data = b""
        try:
            while True:
                chunk = s.recv(1024)
                if not chunk: break
                data += chunk
        except Exception: pass
        s.close()
        return data.decode("utf-8").strip()
    s.close()
    return None

if len(sys.argv) < 2:
    print("Available voices:")
    for v in VOICES: print(f"  {v}")
    sys.exit(0)

if sys.argv[1] == "--current":
    print(f"Current voice: {send('__GETVOICE__', expect_reply=True)}")
    sys.exit(0)

voice = sys.argv[1].strip()
if voice not in VOICES:
    print(f"Unknown voice: {voice}")
    print("Run without arguments to see available voices.")
    sys.exit(1)

send(f"__VOICE:{voice}__")
print(f"Voice changed to: {voice}")
PYEOF

cat > "$KOKORO_DIR/set_speed.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
set_speed.py - Change the TTS speed on the fly without restarting the server.
Usage: python3 set_speed.py 1.3
       python3 set_speed.py --up       (increase by 0.2)
       python3 set_speed.py --down     (decrease by 0.2)
       python3 set_speed.py --current
"""
import sys, socket

PORT = 59001
STEP = 0.2

def send(msg, expect_reply=False):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", PORT))
    s.sendall(msg.encode("utf-8"))
    s.shutdown(socket.SHUT_WR)
    if expect_reply:
        data = b""
        try:
            while True:
                chunk = s.recv(1024)
                if not chunk: break
                data += chunk
        except Exception: pass
        s.close()
        return data.decode("utf-8").strip()
    s.close()
    return None

if len(sys.argv) < 2:
    print("Usage: python3 set_speed.py SPEED  (e.g. 1.3)")
    print("       python3 set_speed.py --up")
    print("       python3 set_speed.py --down")
    print("       python3 set_speed.py --current")
    sys.exit(0)

if sys.argv[1] == "--current":
    print(f"Current speed: {send('__GETSPEED__', expect_reply=True)}")
    sys.exit(0)

if sys.argv[1] in ("--up", "--down"):
    current = send("__GETSPEED__", expect_reply=True)
    try:
        current = float(current)
    except:
        print("Could not read current speed from server.")
        sys.exit(1)
    speed = round(current + (STEP if sys.argv[1] == "--up" else -STEP), 2)
    speed = max(0.5, min(2.5, speed))
    send(f"__SPEED:{speed}__")
    print(f"Speed changed to: {speed}x")
    sys.exit(0)

try:
    speed = float(sys.argv[1])
    assert 0.5 <= speed <= 2.5
except:
    print("Speed must be a number between 0.5 and 2.5")
    sys.exit(1)

send(f"__SPEED:{speed}__")
print(f"Speed changed to: {speed}x")
PYEOF

echo "      Done."

# --- 6. Write shell scripts --------------------------------------------------
# tts_preview.py - friendly preview phrase router
cat > "$KOKORO_DIR/tts_preview.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""tts_preview.py - friendly voice-preview command router for Kokoro TTS.

Accepted examples:
  quick preview voices
  preview all voices
  preview voice onyx
  __PREVIEW_QUICK__

Exit codes:
  0 = preview command recognized/handled
  1 = malformed preview command or unknown voice
  2 = not a preview command
"""

import os
import re
import socket
import subprocess
import sys
import time

HOST, PORT = "127.0.0.1", 59001

VOICES = {
    "American male": ["am_onyx", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_santa"],
    "American female": ["af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky"],
    "British female": ["bf_alice", "bf_emma", "bf_isabella", "bf_lily"],
    "British male": ["bm_daniel", "bm_fable", "bm_george", "bm_lewis"],
}

# One short representative per category for quick preview.
CATEGORY_REPS = {
    "American male": ["am_onyx"],
    "American female": ["af_sky"],
    "British female": ["bf_emma"],
    "British male": ["bm_daniel"],
}

SAMPLE = "Hello! This is how I sound. You can ask to switch to this voice anytime."
QUICK_PHRASES = {
    "quick preview voices",
    "quick voice preview",
    "preview voices",
    "voice preview",
}
FULL_PHRASES = {
    "preview all voices",
    "full preview voices",
    "play all voices",
}
SINGLE_RE = re.compile(r"^(preview|test|hear) voice ([a-z0-9_ -]+)$")

ALL_VOICES = [voice for voices in VOICES.values() for voice in voices]
ALIASES = {}
for voice in ALL_VOICES:
    suffix = voice.split("_", 1)[1]
    ALIASES.setdefault(suffix, []).append(voice)
    ALIASES.setdefault(voice, []).append(voice)


def normalize(text):
    text = (text or "").strip().strip('"\'')
    text = text.replace("\u201c", '"').replace("\u201d", '"').replace("\u2018", "'").replace("\u2019", "'")
    text = text.lower()
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def resolve_voice(name):
    key = normalize(name).replace(" ", "_").replace("-", "_")
    if key in ALL_VOICES:
        return key
    matches = ALIASES.get(key, [])
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise ValueError(f"Ambiguous voice alias '{name}': {', '.join(matches)}")
    raise ValueError(f"Unknown voice '{name}'. Try a full voice ID like am_onyx or af_sky.")


def parse_command(raw):
    original = (raw or "").strip()
    text = normalize(original)
    upper = original.upper().strip()

    if upper == "__PREVIEW_QUICK__":
        return ("quick", None)
    if upper == "__PREVIEW_ALL__":
        return ("all", None)
    if upper.startswith("__PREVIEW_VOICE__:"):
        return ("voice", resolve_voice(original.split(":", 1)[1].strip()))

    if text in QUICK_PHRASES:
        return ("quick", None)
    if text in FULL_PHRASES:
        return ("all", None)

    match = SINGLE_RE.fullmatch(text)
    if match:
        return ("voice", resolve_voice(match.group(2).strip()))

    # Phrases that look like a preview request but are not whitelisted should fail loudly.
    if text.startswith(("preview", "test voice", "hear voice")):
        raise ValueError("Preview command not recognized. Try 'quick preview voices', 'preview all voices', or 'preview voice onyx'.")

    return (None, None)


def display_action(mode, voice=None):
    if mode == "quick":
        return "preview_voices.py --category"
    if mode == "all":
        return "preview_voices.py"
    if mode == "voice":
        return f"preview_voices.py {voice}"
    return "not a preview command"


def send(text, timeout=5):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((HOST, PORT))
        s.sendall(text.encode("utf-8"))


def send_recv(text, timeout=5):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((HOST, PORT))
        s.sendall(text.encode("utf-8"))
        s.shutdown(socket.SHUT_WR)
        data = b""
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
    return data.decode("utf-8", errors="replace").strip()


def get_current_voice():
    try:
        return send_recv("__GETVOICE__") or "am_onyx"
    except Exception:
        return "am_onyx"


def set_voice(name):
    send(f"__VOICE:{name}__")


def stop_speech():
    try:
        send("__STOP__", timeout=1)
    except Exception:
        pass


def preview_voice(category, name, delay=5.0):
    label = f"{category} - {name.split('_', 1)[1]}"
    print(f"  {label}", flush=True)
    # Carry the voice in the request itself (VOICE=name|text) so each sample is
    # synthesised with its own voice atomically. Setting a shared global and then
    # sending the text separately races: threaded synthesis could read a voice the
    # next sample already overwrote, so a sample plays in the wrong voice.
    send(f"VOICE={name}|{label}. {SAMPLE}")
    time.sleep(delay)


def run_preview(mode, voice=None):
    original = get_current_voice()
    print(f"Starting voice preview. Will restore '{original}' when done.", flush=True)
    try:
        if mode == "voice":
            category = next((cat for cat, names in VOICES.items() if voice in names), "Voice")
            preview_voice(category, voice, delay=6.0)
        elif mode == "quick":
            for category, names in CATEGORY_REPS.items():
                print(f"[{category}]", flush=True)
                for name in names:
                    preview_voice(category, name, delay=6.0)
        elif mode == "all":
            for category, names in VOICES.items():
                print(f"[{category}]", flush=True)
                for name in names:
                    preview_voice(category, name, delay=4.5)
    except KeyboardInterrupt:
        stop_speech()
        print("Stopped.", flush=True)
    finally:
        try:
            set_voice(original)
            time.sleep(0.2)
        except Exception:
            pass
        print("Voice preview done.", flush=True)


def launch_background(mode, voice=None):
    args = [sys.executable, os.path.abspath(__file__), "--run-preview", mode]
    if voice:
        args.append(voice)
    kwargs = {}
    if os.name == "nt":
        kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)


def main(argv):
    dry_run = False
    args = list(argv)
    if "--run-preview" in args:
        idx = args.index("--run-preview")
        mode = args[idx + 1] if len(args) > idx + 1 else ""
        voice = args[idx + 2] if len(args) > idx + 2 else None
        if mode not in {"quick", "all", "voice"}:
            print("Invalid internal preview mode.", file=sys.stderr)
            return 1
        run_preview(mode, voice)
        return 0

    if "--dry-run" in args:
        dry_run = True
        args.remove("--dry-run")

    raw = " ".join(args).strip()
    if not raw:
        print("No preview command provided.", file=sys.stderr)
        return 2

    try:
        mode, voice = parse_command(raw)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if not mode:
        print("Not a preview command.")
        return 2

    action = display_action(mode, voice)
    if dry_run:
        print(action)
        return 0

    launch_background(mode, voice)
    print(f"Starting: {action}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PYEOF
chmod +x "$KOKORO_DIR/tts_preview.py"
echo "[6/11] Writing shell scripts..."

cat > "$CLAUDE_DIR/tts_hook.sh" << SHEOF
#!/bin/bash
TOGGLE_FILE="\$HOME/.claude/tts_enabled.txt"
TTS_SCRIPT="\$HOME/.claude/kokoro/tts_speak.py"
TTS_SERVER="\$HOME/.claude/kokoro/tts_server.py"
PORT=$PORT

if [ ! -f "\$TOGGLE_FILE" ]; then exit 0; fi
STATE=\$(tr '[:upper:]' '[:lower:]' < "\$TOGGLE_FILE" | tr -d '[:space:]')
if [ "\$STATE" != "on" ]; then exit 0; fi

STDIN_CONTENT=\$(cat)
if [ -z "\$STDIN_CONTENT" ]; then exit 0; fi

TEXT=\$(echo "\$STDIN_CONTENT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('last_assistant_message', ''), end='')
except: pass
" 2>/dev/null)

if [ -z "\$TEXT" ]; then exit 0; fi

# Only the persistent server may produce audio — it alone understands stop and
# serialises requests. Never synthesise directly (that was a second, unstoppable
# voice). If the server is busy or still booting (~10s to load the model), wait and
# retry for up to ~60s; a short delay is fine, overlapping/unstoppable audio is not.
i=0
started=0
while [ \$i -lt 60 ]; do
    if echo "\$TEXT" | python3 -c "
import sys, socket
data = sys.stdin.buffer.read()
try:
    s = socket.socket(); s.settimeout(3)
    s.connect(('127.0.0.1', \$PORT)); s.sendall(data); s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        exit 0
    fi
    if [ \$started -eq 0 ] && ! pgrep -f tts_server.py >/dev/null 2>&1; then
        python3 "\$TTS_SERVER" >/dev/null 2>&1 &
        started=1
    fi
    sleep 1
    i=\$((i + 1))
done
exit 0
SHEOF
chmod +x "$CLAUDE_DIR/tts_hook.sh"

cat > "$CLAUDE_DIR/toggle_tts.sh" << SHEOF
#!/bin/bash
FILE="\$HOME/.claude/tts_enabled.txt"
if [ "\$1" = "on" ] || [ "\$1" = "off" ]; then
    echo "\$1" > "\$FILE"; echo "TTS \$1"; exit 0
fi
if [ ! -f "\$FILE" ]; then echo "on" > "\$FILE"; echo "TTS on"
else
    STATE=\$(cat "\$FILE" | tr -d '[:space:]')
    if [ "\$STATE" = "on" ]; then echo "off" > "\$FILE"; echo "TTS off"
    else echo "on" > "\$FILE"; echo "TTS on"; fi
fi
SHEOF
chmod +x "$CLAUDE_DIR/toggle_tts.sh"

cat > "$CLAUDE_DIR/restart_tts.sh" << SHEOF
#!/bin/bash
LABEL="$PLIST_LABEL"
launchctl bootout "gui/\$(id -u)/\$LABEL" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/\$(id -u)" "\$HOME/Library/LaunchAgents/\$LABEL.plist"
echo "TTS server restarted."
SHEOF
chmod +x "$CLAUDE_DIR/restart_tts.sh"

cat > "$CLAUDE_DIR/stop_tts.sh" << SHEOF
#!/bin/bash
python3 -c "
import socket
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', $PORT))
    s.sendall(b'__STOP__')
    s.close()
except: pass
"
SHEOF
chmod +x "$CLAUDE_DIR/stop_tts.sh"

cat > "$CLAUDE_DIR/status_tts.sh" << 'SHEOF'
#!/bin/bash
if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',59001)); s.close()" 2>/dev/null; then
    echo "TTS server is running."
else
    echo "TTS server is NOT running. Run: bash ~/.claude/restart_tts.sh"
fi
SHEOF
chmod +x "$CLAUDE_DIR/status_tts.sh"

cat > "$CLAUDE_DIR/uninstall_tts.sh" << SHEOF
#!/bin/bash
# =============================================================================
# uninstall_tts.sh - Remove Claude Code TTS (Kokoro) from this machine.
# =============================================================================

LABEL="$PLIST_LABEL"
PLIST="$PLIST_PATH"
CLAUDE_DIR="\$HOME/.claude"

echo ""
echo "============================================"
echo " Claude Code TTS Uninstaller"
echo "============================================"
echo ""

echo "[1/5] Stopping TTS server and hotkey daemon..."
launchctl bootout "gui/\$(id -u)/\$LABEL" 2>/dev/null || true
pkill -f tts_server.py 2>/dev/null || true
launchctl bootout "gui/\$(id -u)/com.user.kokoro-tts-hotkey" 2>/dev/null || true
pkill -f tts_hotkey.py 2>/dev/null || true
echo "      Done."

echo "[2/5] Removing launchd plists..."
rm -f "\$PLIST"
rm -f "\$HOME/Library/LaunchAgents/com.user.kokoro-tts-hotkey.plist"
echo "      Done."

echo "[3/5] Removing Automator stop shortcut..."
rm -rf "\$HOME/Library/Services/Stop TTS.workflow"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "      Done."

echo "[4/5] Removing hook from settings.json..."
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/settings.json')
if not os.path.exists(path): exit(0)
with open(path) as f: s = json.load(f)
if 'Stop' in s.get('hooks', {}):
    s['hooks']['Stop'][0]['hooks'] = [
        h for h in s['hooks']['Stop'][0]['hooks'] if 'tts_hook' not in h.get('command','')
    ]
    with open(path, 'w') as f: json.dump(s, f, indent=2)
    print('      Done.')
else:
    print('      Hook not found, skipping.')
"

echo "[5/5] Removing TTS files..."
rm -f "\$CLAUDE_DIR/tts_hook.sh" "\$CLAUDE_DIR/tts_enabled.txt"
rm -f "\$CLAUDE_DIR/toggle_tts.sh" "\$CLAUDE_DIR/restart_tts.sh"
rm -f "\$CLAUDE_DIR/stop_tts.sh" "\$CLAUDE_DIR/status_tts.sh"
rm -f "\$CLAUDE_DIR/uninstall_tts.sh" "\$CLAUDE_DIR/CLAUDE.md"
rm -rf "\$CLAUDE_DIR/kokoro"
echo "      Done."

echo ""
echo "============================================"
echo " TTS removed. Python packages (kokoro-onnx,"
echo " sounddevice, numpy) were left in place."
echo " Remove with: pip3 uninstall kokoro-onnx sounddevice"
echo "============================================"
echo ""
SHEOF
chmod +x "$CLAUDE_DIR/uninstall_tts.sh"

# CLAUDE.md
cat > "$CLAUDE_DIR/CLAUDE.md" << SHEOF
# Claude Code — Global Instructions

## Text-to-Speech

A local Kokoro TTS server runs on port 59001. Every assistant response is spoken automatically via the Stop hook — no action needed from Claude.

### Changing the voice
When the user asks to change the voice, run:
    python3 $KOKORO_DIR/set_voice.py VOICENAME

IMPORTANT: Never change the user's voice unless they explicitly ask.

Available voices:
- American male:   am_onyx (default), am_adam, am_echo, am_eric, am_fenrir, am_liam, am_michael, am_santa
- American female: af_alloy, af_aoede, af_bella, af_heart, af_jessica, af_kore, af_nicole, af_nova, af_river, af_sarah, af_sky
- British female:  bf_alice, bf_emma, bf_isabella, bf_lily
- British male:    bm_daniel, bm_fable, bm_george, bm_lewis

### Checking current voice
    python3 $KOKORO_DIR/set_voice.py --current

### Changing speed
When the user says "speak faster" or "speak slower", run:
    python3 $KOKORO_DIR/set_speed.py --up
    python3 $KOKORO_DIR/set_speed.py --down
When the user gives a specific speed (e.g. "set speed to 1.5"), run:
    python3 $KOKORO_DIR/set_speed.py 1.5
Speed range: 0.5 (slow) to 2.5 (fast). Step size: 0.2x.

### Other controls
    bash $CLAUDE_DIR/toggle_tts.sh on|off    (toggle TTS)
    bash $CLAUDE_DIR/restart_tts.sh          (restart server)
    bash $CLAUDE_DIR/status_tts.sh           (check server)
    bash $CLAUDE_DIR/stop_tts.sh             (stop current speech)

### Hook note
The Stop hook uses bash (tts_hook.sh). Do NOT change it to a background process — it must complete synchronously to ensure the response is spoken.
SHEOF

echo "on" > "$CLAUDE_DIR/tts_enabled.txt"
echo "      Done."

# --- 7. Update settings.json -------------------------------------------------
echo "[7/11] Updating Claude Code settings.json..."
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash $CLAUDE_DIR/tts_hook.sh"

$PYTHON - << PYEOF
import json, os, sys

path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "$HOOK_CMD"

if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
else:
    settings = {"hooks": {}}

if "hooks" not in settings:
    settings["hooks"] = {}

new_hook = {"type": "command", "command": hook_cmd, "async": True}

if "Stop" not in settings["hooks"]:
    settings["hooks"]["Stop"] = [{"hooks": [new_hook]}]
else:
    existing = settings["hooks"]["Stop"][0]["hooks"]
    if not any("tts_hook" in h.get("command","") for h in existing):
        existing.append(new_hook)
    else:
        print("      Hook already present, skipping.")
        sys.exit(0)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
echo "      Done."

# --- 8. Set up launchd auto-start --------------------------------------------
echo "[8/11] Setting up launchd auto-start and launching server..."

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$KOKORO_DIR/tts_server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.claude/tts_server.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/tts_server.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true

# --- Ctrl+Option+X global stop hotkey (Carbon RegisterEventHotKey; NO permission prompt) ---
HOTKEY_PLIST_LABEL="com.user.kokoro-tts-hotkey"
HOTKEY_PLIST_PATH="$HOME/Library/LaunchAgents/$HOTKEY_PLIST_LABEL.plist"
cat > "$KOKORO_DIR/tts_hotkey.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
Safe global TTS hotkey daemon (macOS).
Registers Ctrl+Option+X via Carbon's RegisterEventHotKey and sends Kokoro's
shared __STOP__ command to 127.0.0.1:59001. RegisterEventHotKey is NOT gated by
Accessibility or Input Monitoring, so NO permission prompt is ever shown —
unlike a pynput / CGEventTap approach.
"""
import ctypes
import ctypes.util
import os
import socket
import time
import traceback

HOST = "127.0.0.1"
PORT = 59001
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs", "tts_hotkey.log")

# Carbon modifier masks (these are NOT CGEventFlags values):
CONTROL_KEY = 0x1000
OPTION_KEY  = 0x0800
KEY_X       = 0x07                 # kVK_ANSI_X
KEY_R       = 0x0F                 # kVK_ANSI_R
EVENT_CLASS_KEYBOARD = 0x6B657962  # 'keyb'
EVENT_HOTKEY_PRESSED = 5           # kEventHotKeyPressed
PARAM_DIRECT_OBJECT  = 0x2D2D2D2D  # '----' kEventParamDirectObject
TYPE_HOTKEY_ID       = 0x686B6964  # 'hkid' typeEventHotKeyID
STOP_ID   = 1
REPLAY_ID = 2
kProcessTransformToUIElementApplication = 4


def log(message):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}"
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _send(cmd, label):
    try:
        with socket.create_connection((HOST, PORT), timeout=1.0) as sock:
            sock.sendall(cmd)
        log(f"{label} sent {cmd.decode()}")
    except Exception as exc:
        log(f"{label} failed to send {cmd.decode()}: {exc}")


def send_stop():
    _send(b"__STOP__", "Ctrl+Option+X")


def send_replay():
    _send(b"__REPLAY__", "Ctrl+Option+R")


class EventTypeSpec(ctypes.Structure):
    _fields_ = [("eventClass", ctypes.c_uint32), ("eventKind", ctypes.c_uint32)]


class EventHotKeyID(ctypes.Structure):
    _fields_ = [("signature", ctypes.c_uint32), ("id", ctypes.c_uint32)]


class ProcessSerialNumber(ctypes.Structure):
    _fields_ = [("highLongOfPSN", ctypes.c_uint32), ("lowLongOfPSN", ctypes.c_uint32)]


carbon = None  # set in main()

# OSStatus handler(EventHandlerCallRef, EventRef, void *userData)
HANDLER = ctypes.CFUNCTYPE(ctypes.c_int32, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)


def _on_hotkey(_call_ref, event, _user_data):
    hk = EventHotKeyID()
    try:
        carbon.GetEventParameter(event, PARAM_DIRECT_OBJECT, TYPE_HOTKEY_ID, None,
                                 ctypes.sizeof(hk), None, ctypes.byref(hk))
    except Exception:
        pass
    if hk.id == REPLAY_ID:
        send_replay()
    else:
        send_stop()
    return 0


# Keep a reference so the trampoline isn't garbage-collected.
_handler_ref = HANDLER(_on_hotkey)


def _load_carbon():
    # ctypes.util.find_library("Carbon") returns None on macOS 11+ because system
    # frameworks live in the dyld shared cache, not on disk. Load by absolute
    # path first; dyld still resolves it from the cache.
    for path in ("/System/Library/Frameworks/Carbon.framework/Carbon",
                 "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon",
                 ctypes.util.find_library("Carbon")):
        if not path:
            continue
        try:
            return ctypes.CDLL(path)
        except OSError:
            continue
    return None


def main():
    global carbon
    carbon = _load_carbon()
    if carbon is None:
        log("ERROR: could not load the Carbon framework; hotkey disabled.")
        return
    try:
        carbon.GetApplicationEventTarget.restype = ctypes.c_void_p
        carbon.GetApplicationEventTarget.argtypes = []
        carbon.GetEventParameter.restype = ctypes.c_int32
        carbon.GetEventParameter.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
                                             ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]
        carbon.InstallEventHandler.restype = ctypes.c_int32
        carbon.InstallEventHandler.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong,
                                               ctypes.POINTER(EventTypeSpec), ctypes.c_void_p, ctypes.c_void_p]
        carbon.RegisterEventHotKey.restype = ctypes.c_int32
        carbon.RegisterEventHotKey.argtypes = [ctypes.c_uint32, ctypes.c_uint32, EventHotKeyID,
                                               ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
        carbon.RunApplicationEventLoop.restype = None
        carbon.RunApplicationEventLoop.argtypes = []

        # Give the faceless launchd process a WindowServer connection so it can
        # receive the hotkey, without showing a Dock icon.
        try:
            psn = ProcessSerialNumber(0, 2)  # {0, kCurrentProcess}
            carbon.TransformProcessType(ctypes.byref(psn),
                                        kProcessTransformToUIElementApplication)
        except Exception as exc:
            log(f"TransformProcessType skipped: {exc}")

        target = carbon.GetApplicationEventTarget()
        spec = EventTypeSpec(EVENT_CLASS_KEYBOARD, EVENT_HOTKEY_PRESSED)
        carbon.InstallEventHandler(target, _handler_ref, 1, ctypes.byref(spec), None, None)

        stop_ref = ctypes.c_void_p()
        status = carbon.RegisterEventHotKey(KEY_X, CONTROL_KEY | OPTION_KEY,
                                            EventHotKeyID(0x54545353, STOP_ID), target, 0,
                                            ctypes.byref(stop_ref))
        if status != 0:
            log(f"RegisterEventHotKey(stop) FAILED (status {status}); Ctrl+Option+X may be taken.")
            return
        replay_ref = ctypes.c_void_p()
        status_r = carbon.RegisterEventHotKey(KEY_R, CONTROL_KEY | OPTION_KEY,
                                              EventHotKeyID(0x54545353, REPLAY_ID), target, 0,
                                              ctypes.byref(replay_ref))
        if status_r != 0:
            log(f"RegisterEventHotKey(replay) FAILED (status {status_r}); Ctrl+Option+R may be taken.")
        log("Registered Ctrl+Option+X (stop) and Ctrl+Option+R (replay) (Carbon, no permission needed).")
        carbon.RunApplicationEventLoop()
    except Exception as exc:
        log("ERROR in hotkey daemon: " + repr(exc))
        log(traceback.format_exc())


if __name__ == "__main__":
    main()
PYEOF
cat > "$HOTKEY_PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$HOTKEY_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$KOKORO_DIR/tts_hotkey.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.claude/tts_hotkey.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/tts_hotkey.log</string>
</dict>
</plist>
PLISTEOF
launchctl bootout "gui/$(id -u)/$HOTKEY_PLIST_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOTKEY_PLIST_PATH" 2>/dev/null || true
echo "      Ctrl+Option+X (stop) and Ctrl+Option+R (replay) hotkeys installed (no permission prompt needed)."

echo "      Waiting for server to load model (~10 seconds)..."
sleep 10

if python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1',$PORT)); s.close()" 2>/dev/null; then
    echo "      Server running."
else
    echo -e "      ${YELLOW}WARNING: Server did not respond. Try running: bash ~/.claude/restart_tts.sh${NC}"
fi

echo ""
echo "============================================"
echo " Setup complete!"
echo "============================================"
echo ""
echo " Version: v$VERSION  |  Voice: am_onyx  |  Speed: 1.1x"
echo ""
echo " Toggle:       tell Claude 'turn voice on' or 'turn voice off'"
echo " Change voice: tell Claude 'switch to voice sky'"
echo "               27 voices — American and British, male and female"
echo " Change speed: tell Claude 'speak faster' or 'speak slower'"
echo "               or: python3 ~/.claude/kokoro/set_speed.py 1.3"
echo " Stop:         press Ctrl+Option+X"
echo " Replay:       press Ctrl+Option+R"
echo " Preview:      tell Claude 'quick preview voices' or 'preview all voices'"
echo " Status:       bash ~/.claude/status_tts.sh"
echo " Uninstall:    bash ~/.claude/uninstall_tts.sh"
echo ""

# --- 10. Write Cowork watcher (macOS version) --------------------------------
echo "[10/11] Writing Cowork session watcher (tts_watcher.py v4.11 macOS)..."

mkdir -p "$COWORK_DIR"

cat > "$COWORK_DIR/tts_watcher.py" << 'PYEOF'
# -*- coding: utf-8 -*-
# tts_watcher.py v4.11 - Automatic TTS for Claude Cowork sessions.
# Monitors the Cowork session transcript (JSONL) and speaks assistant messages.
# Also monitors tts_queue.txt for special commands (voice previews, etc.)
# Regular CLI sessions are handled by the Stop hook (tts_hook.ps1) instead.
#
# Double-speaking fix: Claude no longer writes to tts_queue.txt for regular
# responses — the queue file is reserved for special commands only.
#
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
if sys.platform == "darwin":
    SESSIONS_DIR = os.path.expanduser("~/Library/Application Support/Claude/local-agent-mode-sessions")
else:
    APPDATA      = os.environ.get("APPDATA", os.path.expanduser("~\\AppData\\Roaming"))
    SESSIONS_DIR = os.path.join(APPDATA, "Claude", "local-agent-mode-sessions")
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
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(payload.encode("utf-8"))
        log(f"Spoke {len(text)} chars")
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
    """Route legacy preview tokens and friendly phrases through the installed helper."""
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

# --- Main loop ---
log("tts_watcher v4.11 started. Monitoring Cowork transcript + queue commands.")
load_state()

while True:
    try:
        check_jsonl()
        check_queue()
    except Exception as e:
        log(f"Loop error: {e}")
    time.sleep(POLL)
PYEOF
chmod +x "$COWORK_DIR/tts_watcher.py"

# Watchdog script for macOS
cat > "$COWORK_DIR/watchdog.sh" << 'SHEOF'
#!/bin/bash
# watchdog.sh v2 - Monitors Kokoro server and Cowork watcher, restarts if down.
# v2: heartbeat log every 5 minutes, launchd-aware restart.
KOKORO_DIR="$HOME/.claude/kokoro"
WATCHER_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$WATCHER_DIR/tts_watcher_log.txt"
PORT=59001
CHECK_INTERVAL=30
PYTHON=$(command -v python3)
HEARTBEAT_SECS=300
last_heartbeat=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WATCHDOG: $1" >> "$LOG"; }
is_server_up() { "$PYTHON" -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',$PORT)); s.close()" 2>/dev/null; }
is_watcher_up() { pgrep -f "tts_watcher.py" > /dev/null 2>&1; }

log "Watchdog started."
while true; do
    sleep "$CHECK_INTERVAL"
    now=$(date +%s)
    if ! is_server_up; then
        log "Server down - restarting"
        "$PYTHON" "$KOKORO_DIR/tts_server.py" &
        sleep 5
    fi
    if ! is_watcher_up; then
        log "Watcher down - restarting"
        "$PYTHON" "$WATCHER_DIR/tts_watcher.py" &
        sleep 2
    fi
    if (( now - last_heartbeat >= HEARTBEAT_SECS )); then
        log "Heartbeat OK"
        last_heartbeat=$now
    fi
done
SHEOF
chmod +x "$COWORK_DIR/watchdog.sh"

: > "$COWORK_DIR/tts_queue.txt"

echo "      Done: $COWORK_DIR"

# --- 11. Set up Cowork watcher launchd plist + launch -----------------------
echo "[11/11] Setting up Cowork watcher auto-start and launching..."

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$WATCHER_PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$WATCHER_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$COWORK_DIR/tts_watcher.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$COWORK_DIR/tts_watcher_log.txt</string>
    <key>StandardErrorPath</key>
    <string>$COWORK_DIR/tts_watcher_log.txt</string>
</dict>
</plist>
PLISTEOF

# Bootstrap watcher via launchd (auto-restart at login)
launchctl bootstrap "gui/$(id -u)" "$WATCHER_PLIST_PATH" 2>/dev/null || true

# Launch watchdog in background now
nohup bash "$COWORK_DIR/watchdog.sh" >> "$COWORK_DIR/tts_watcher_log.txt" 2>&1 &

echo "      Done."

echo ""
echo "============================================"
echo " Installation complete!"
echo "============================================"
echo ""
echo " Kokoro TTS server + Cowork watcher are running."
echo " Both start automatically at every login."
echo ""
echo " Voice:   am_onyx (default) | 27 voices available"
echo " Speed:   1.2x"
echo " Stop:    Ctrl+Option+X (< 50ms response)"
echo " Replay:  Ctrl+Option+R"
echo ""
echo " Watcher log:  $COWORK_DIR/tts_watcher_log.txt"
echo " Restart watcher: launchctl kickstart gui/$(id -u)/$WATCHER_PLIST_LABEL"
echo " Uninstall:    bash $CLAUDE_DIR/uninstall_tts.sh"
echo "============================================"
echo ""

