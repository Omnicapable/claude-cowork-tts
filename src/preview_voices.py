# -*- coding: utf-8 -*-
# preview_voices.py - Cycle through all Kokoro voices so you can hear them before choosing.
# Usage: python preview_voices.py              (all voices)
#        python preview_voices.py --category   (one rep per category)
#        python preview_voices.py am_onyx      (single voice test)

import socket
import time
import sys

HOST, PORT = "127.0.0.1", 59001

VOICES = {
    "American male":   ["am_onyx", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_santa"],
    "American female": ["af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky"],
    "British female":  ["bf_alice", "bf_emma", "bf_isabella", "bf_lily"],
    "British male":    ["bm_daniel", "bm_fable", "bm_george", "bm_lewis"],
}

# Representatives per category for quick preview
CATEGORY_REPS = {
    "American male":   ["am_onyx", "am_echo"],
    "British female":  ["bf_emma"],
    "British male":    ["bm_daniel"],
    "American female": ["af_alloy", "af_heart", "af_nicole"],
}

SAMPLE = "Hello! This is how I sound. You can ask Claude to switch to this voice anytime."

def send(text):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(text.encode("utf-8"))
        return True
    except Exception as e:
        print(f"  [error] Could not connect to Kokoro: {e}")
        return False

def send_recv(text):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(text.encode("utf-8"))
            s.shutdown(socket.SHUT_WR)
            data = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
        return data.decode("utf-8").strip()
    except Exception:
        return None

def get_current_voice():
    voice = send_recv("__GETVOICE__")
    return voice if voice else "am_onyx"

def set_voice(name):
    return send(f"__VOICE:{name}__")

def speak(text):
    return send(text)

def preview_voice(category, name, delay=4.5):
    label = f"{category} -- {name.split('_', 1)[1]}"
    print(f"  {label}")
    set_voice(name)
    time.sleep(0.2)
    speak(f"{label}. {SAMPLE}")
    time.sleep(delay)

def restore_voice(original):
    set_voice(original)
    time.sleep(0.2)

def main():
    args = sys.argv[1:]

    # Single voice test
    if args and not args[0].startswith("--"):
        name = args[0]
        cat = next((c for c, vs in VOICES.items() if name in vs), "Unknown")
        original = get_current_voice()
        print(f"Testing voice: {name} (will restore {original} after)")
        preview_voice(cat, name, delay=6)
        restore_voice(original)
        print("Done.")
        return

    # Category reps only
    if "--category" in args:
        original = get_current_voice()
        print(f"Playing selected voices. Will restore '{original}' when done. Press Ctrl+C to stop.\n")
        try:
            for cat, names in CATEGORY_REPS.items():
                print(f"[{cat}]")
                for name in names:
                    preview_voice(cat, name, delay=8)
        except KeyboardInterrupt:
            send("__STOP__")
            restore_voice(original)
            print("\nStopped.")
            return
        restore_voice(original)
        time.sleep(0.2)
        speak("That was a quick selection. There are over 20 other voices available. Just ask Claude to preview all voices, or say switch to any voice name you heard.")
        print("\nDone. Ask Claude to switch to any voice you liked.")
        return

    # All voices
    original = get_current_voice()
    print(f"Playing all voices. Will restore '{original}' when done. Press Ctrl+C to stop.\n")
    try:
        for cat, names in VOICES.items():
            print(f"[{cat}]")
            for name in names:
                preview_voice(cat, name, delay=5)
            print()
    except KeyboardInterrupt:
        send("__STOP__")
        restore_voice(original)
        print("\nStopped.")
        return

    restore_voice(original)
    print("Done. Ask Claude to switch to any voice you liked.")

if __name__ == "__main__":
    main()
