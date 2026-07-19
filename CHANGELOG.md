# Claude Cowork TTS — Changelog

Lightweight public summary. Full detail lives in `Claude Cowork TTS - Changelog.docx` in the source folder.

---

## Shared server v2.6

**Smoother playback under load**

- **No more gaps between sentences when the machine is busy.** The server now raises
  its own process priority at startup (Windows: `SetPriorityClass` ABOVE_NORMAL;
  Mac/Linux: best-effort `os.nice`), so the next sentence is always synthesized before
  the current one finishes playing, even while the CPU is loaded by the agent or a
  browser. Previously that contention produced audible pauses between sentences.

## Shared server v2.5

**Improved speech**

- **Speed survives a restart too.** The chosen speed is saved to `speed.txt` beside the
  server (mirroring voice memory in `voice.txt`) and reloaded on start, so it no longer
  resets to the default after a reboot.
- **Abbreviations are finally spoken.** `e.g.`, `i.e.`, `vs.`, `etc.`, `approx.` were never
  expanded — their patterns ended in a word boundary that cannot match before a space, so the
  rules existed but never fired. They now read "for example", "that is", "versus",
  "etcetera", "approximately".
- **Money reads naturally in more shapes.** `$3.5` reads "3 dollars and 50 cents" (the
  ".5" used to be left dangling after "3 dollars"), `$0.99` reads "99 cents", `$1.5 million`
  and `$1.5M` read "1 point 5 million dollars" (scale words thousand/million/billion/trillion
  plus attached suffixes k/M/B), and odd precision like `$12.345` falls back to
  "12 point 345 dollars". `$3.50` and `$1,234.56` read exactly as before.
- **More emoji and symbols stripped.** The star/symbol and arrow blocks (U+2B00-2BFF,
  U+2190-21FF — e.g. star and left-right-arrow glyphs) no longer reach the voice.

**Cleanup**

- **Dead fallback removed.** The Claude Code and Cowork installers wrote `tts_speak.py` and
  set an unused `$ttsScript`/`TTS_SCRIPT` variable pointing at it; nothing ever invoked
  either. Both are gone. The persistent server remains the only audio path, unchanged.
  Existing installs keep an inert `tts_speak.py` on disk; it is harmless.

All six embedded servers and the three `src/` copies remain byte-identical (v2.5).

---

## Shared server v2.4

**Fixed**

- **Mid-reply silence.** Long sentences became single oversized chunks (200+ chars); when
  one followed a short chunk, playback caught up with synthesis and speech stalled for a
  couple of seconds. Sentences now split at clause breaks (commas, semicolons) into chunks
  of at most ~120 characters, and fragments under ~40 merge with a neighbour. Synthesis on
  CPU runs about 4x realtime, so with uniform chunks the synthesizer always finishes the
  next chunk before the current one ends. Measured on a real reply: zero gaps.
- **Speech starts sooner.** A short opening sentence is no longer glued onto a following
  long one, so the first chunk stays small. Measured time-to-first-audio on a typical
  reply: 1.5s, down from 3.6s.

Chunking only: the control protocol, stop/replay hotkeys, queue, and audio path are
untouched. All six embedded servers and the three `src/` copies remain byte-identical
(v2.4).

---

## Shared server v2.3

**New**

- **Your voice now survives a restart.** The chosen voice is saved to `voice.txt` next to the
  server and reloaded on start, so it no longer resets to the default after a reboot or a
  server restart.
- **Version numbers and bare domains are read properly.** `3.11` is spoken "3 point 11",
  `2.3.1` as "2 point 3 point 1", and `claude.ai` as "claude dot ai" (known TLDs only).
  Money is unaffected — `$3.50` still reads "3 dollars and 50 cents". The pronunciation rule
  is deliberately ordered **after** the money rule: a ` point ` substitution applied first
  eats the decimal and produces "3 dollars point 50". That ordering is load-bearing and is
  pinned by a comment in `clean_text()`; do not move it above the money rule.

**Fixed / consolidated**

- **All installers now ship one identical Kokoro server.** Every installer writes the *same*
  file (`~/.claude/kokoro/tts_server.py`, port 59001), but the six embedded copies had drifted
  (six copies ranging from 170 to 192 lines), so **install order silently decided which server
  you ended up with** — installing a second product could silently replace a newer server with
  an older, smaller one (the Codex Mac copy, for example, lacked emoji stripping). All six are now
  byte-identical to a single canonical **v2.3**, so any install order gives the same result.
- **Version header corrected.** The embedded servers advertised `v2.0` / `v2.1` in their
  docstring while actually shipping replay, output-device follow and the money/decimal fixes.
  The header now matches the code and is stamped v2.3.
- **`src/` resynced (was stale).** The published `src/tts_server.py`, `src/tts_hotkey.py` and
  `src/tts_hotkey_mac.py` still held older code: no `__REPLAY__`, a stop-only `Ctrl+Alt+X`
  hotkey daemon, and the previous `pynput` Mac hotkey. The installers shipped the replay
  hotkey while the published source folder did not contain it. `src/` now matches byte-for-byte
  what the installers write.
- **Claude Code Mac reached parity.** Its embedded server was missing voice memory (so the
  chosen voice was lost on restart) and the version/domain pronunciation block. Both added.
- **Cowork gained emoji stripping.** Its server lacked the emoji strip the other products had,
  so emoji could be read aloud. Added to the Windows and Mac servers.
- **Note — `tts_speak.py` is vestigial.** The installers still write it and still set
  `$ttsScript` / `TTS_SCRIPT` to it, but nothing invokes it: the variable is assigned once and
  never used. The "exactly one audio path" guarantee holds. The dead file and variable are
  safe to remove in a later pass.

**Known issue (not fixed here)**

- **Occasional silence mid-reply.** Synthesis and playback already overlap (a producer thread
  synthesizes ahead of the playback loop), so this is *not* a serialization problem. Two real
  causes remain: playback calls `sd.play()`/`sd.wait()` per chunk, which opens and closes an
  output stream for every chunk; and there is no buffer-ahead, so playback starts the instant
  chunk 1 is ready and any slower chunk becomes an audible gap. The synthesis queue is also
  unbounded. Being addressed separately — it touches stop-hotkey semantics and interacts with
  `_refresh_audio_device()`, so it is deliberately not bundled with this release.

---

## v4.13 (current)

- **Mac stop hotkey needs no permission now.** The macOS stop hotkey (Ctrl+Option+X) was rewritten from `pynput` to Carbon `RegisterEventHotKey`, which is not gated by Accessibility / Input Monitoring, so there is no first-use permission prompt. The leftover Automator "Stop TTS" service was removed and `pynput` dropped from the Mac dependencies.
- **Fixed the Mac hotkey failing to start.** On macOS 11+, `ctypes.util.find_library("Carbon")` returns `None` (system frameworks live in the dyld shared cache), so the daemon crashed before registering. It now loads Carbon by absolute path and logs any startup error to `~/.claude/tts_hotkey.log`.
- **Replay the last answer.** New global hotkey — Ctrl+Alt+R (Windows) / Ctrl+Option+R (macOS) — re-speaks the last reply. The shared server stores the last text and handles a new `__REPLAY__` command.
- **Audio follows your output device.** The server refreshes the audio device before each utterance, so switching output (e.g. connecting AirPods or headphones) is picked up without restarting the server.
- **Clearer install docs.** The README manual-install steps now include the full `git clone` + `cd` sequence (with a ZIP fallback), and the Controls list documents stop, replay, speed, voice change, and voice previews.
- **Mac installer fixes (from a Mac install report).** Removed the UTF-8 BOM that broke `./install_cowork_tts_Mac.sh` (the BOM hid the shebang); fixed an empty-string command (`"" >` → `: >`) that aborted the install under `set -e` right before the final step; and the Cowork session watcher now resolves the macOS app-data path (`~/Library/Application Support/Claude/local-agent-mode-sessions`) instead of a hardcoded Windows path, so it can find Cowork transcripts on Mac.
- **Overlapping / looping speech eliminated structurally (reported from a Mac session).** Root cause: two things could produce audio — the persistent server (which serialises requests and honours stop) and a one-off fallback (`tts_speak.py`) that did neither — so when the Stop hook misjudged a busy server as dead, it started a second, independent, **unstoppable** voice. The hook (Mac + Windows) now has **exactly one audio path**: it sends to the single server and, if the server is busy or still booting (~10s), **waits and retries for up to ~60s** rather than ever synthesising directly. Worst case is a short delay; overlapping or uncancellable audio is now structurally impossible.
- **Audio-device follow made non-fragile.** The output-device refresh no longer tears down and re-initialises PortAudio before every utterance (which caused macOS `PaMacCore -50` errors); it only re-scans after an idle gap, so it still follows AirPods/headphone switches without thrashing the audio backend mid-burst.
- **Fallback can no longer play unstoppable audio (Mac + Windows).** When the server was briefly unreachable, the Stop hook used to synthesise directly via `tts_speak.py` — a separate process with no socket and no stop handling, so Ctrl+Option+X / Ctrl+Alt+X could not cancel it. The hook now only ever plays through the server (starting it if needed and retrying); if the server still isn't ready it drops that one utterance rather than speaking through an uncontrollable path.
- **Voice preview: fixed samples playing in the wrong voice.** The preview announced each voice by mutating a shared global (`__VOICE:name__`) and sent the sample as a separate message — but synthesis runs on a background thread, so a fast preview could synthesise a sample *after* the next voice-switch had overwritten the global, playing it in the wrong voice (mismatched label/gender). Each sample now carries its own voice atomically via the per-request `VOICE=name|text` prefix, correct regardless of timing.
- **Install no longer blocked by Homebrew Python (PEP 668).** On macOS with Homebrew's Python, a global `pip install` is refused (externally-managed environment), which aborted setup at the package step. The installer now retries with `--break-system-packages` when it hits this, so it completes.
- **Money and large numbers now read correctly.** The `$` cleaner only handled a single digit and the thousands-comma strip only removed one comma per number, so `$50` was spoken "5 dollars zero" and `1,000,000` became "one thousand, zero zero zero". Both now parse the whole value: `$50` → "50 dollars", `$3.50` → "3 dollars and 50 cents", `1,000,000` → "1000000", `$1,234.56` → "1234 dollars and 56 cents". Plain decimals (`3.14`) and percentages were already correct and are unaffected.

---

## v4.12

- **Friendly Cowork preview commands.** Installers now write bundled `tts_preview.py`; the Cowork queue watcher routes both friendly queue text (`quick preview voices`, `preview all voices`, `preview voice onyx`) and legacy `__PREVIEW_*` tokens through it. Unknown queue text is logged and ignored instead of spoken.
- **Ctrl+Alt+X now actually ships.** Installers previously advertised the stop hotkey but
  installed it disabled (`TTS_ENABLE_GLOBAL_HOTKEY` off). The Windows installer now installs a
  standalone `tts_hotkey.py` (Windows `RegisterHotKey`, no low-level keyboard hook) and the Mac
  installer a `pynput` launchd agent (Ctrl+Option+X). Both auto-start at login, are single-instance
  (mutex / launchd label), and send `__STOP__` to the shared server. macOS additionally requires
  Accessibility permission — the installer prints exactly how to grant it.
- **`restart_tts_watcher.bat` no longer cross-kills Codex.** Its kill filter matched the substring
  `tts_watcher`, which also matched Codex's `codex_tts_watcher.py`. Narrowed to `\tts_watcher.py`
  so it stops only the Cowork watcher. Fixed in both the installer-generated bat and the live copy.

---

## v4.11

- **Age filter field-name fix** — the v4.8 message age filter (`MESSAGE_MAX_AGE_SECONDS = 180`)
  was a silent no-op. It read the timestamp from a field named `ts`, but Claude session
  transcripts store the time in an ISO-8601 field named `timestamp` (e.g.
  `"2026-06-25T02:04:18.591Z"`). Because `ts` was always absent, the `if ts is not None` guard
  skipped the whole check — no message was ever judged stale. This let a burst of 4-day-old
  replies get spoken when the watcher started on a session file with no saved position. **Fix:**
  the filter now reads the ISO-8601 `timestamp` field (parsed via `datetime.fromisoformat`) and
  still accepts a numeric epoch `ts` for backward compatibility. Verified: a 4-day-old message is
  skipped, a current one passes. Applied to `tts_watcher.py` and the embedded watcher in both the
  Windows and Mac installers. Codex TTS was audited and already reads `timestamp` (no change);
  Claude Code TTS is hook-based and cannot replay, so it is unaffected.
- **Live install reconciled** — the running setup had drifted to v4.9 and was missing the v4.10
  per-watcher-voice feature. v4.10 was back-ported into the live `tts_watcher.py` (`WATCHER_VOICE`
  + `VOICE=name|text` send), and the live shared server (`%USERPROFILE%\.claude\kokoro\tts_server.py`)
  was bumped **v2.0 → v2.1** to parse the per-request voice prefix. Change is additive: plain text
  is unaffected, so CLI and Codex TTS behave exactly as before. Verified end-to-end — a
  `VOICE=af_bella|…` request spoke in that voice and left the global voice unchanged.

---

## v4.10

- **Per-watcher voice** — `WATCHER_VOICE = None` constant added to `tts_watcher.py`. Set it to
  any Kokoro voice name (e.g. `"am_onyx"`) to give Cowork TTS its own distinct voice, independent
  of Codex TTS or Claude Code TTS. Uses the `VOICE=name|text` per-request prefix protocol in
  `tts_server.py v2.1` — voice travels with each request, zero race conditions when multiple
  watchers are active simultaneously. Default `None` preserves existing behaviour.
- **Robust Python launcher (Windows)** — the installer, the auto-start launchers, the generated watchdog, and `watchdog.ps1` now invoke Python through the Windows `py -3` launcher instead of bare `python`. `py -3` is PATH-order independent and version-aware, so on machines with more than one Python install the watcher and Kokoro server always start under Python 3.x — fixing silent failures when bare `python` resolved to an unexpected interpreter. `watchdog.ps1` resolves a concrete interpreter path at startup and falls back to `python`/`python3` if the launcher is absent. Process detection (`Get-Process python`) is unchanged. **Mac is unaffected** — its installer already resolves `python3` once into `$PYTHON` and reuses it everywhere.

---

## v4.9

- **Single-instance lock** — on startup the watcher binds a UDP socket to `127.0.0.1:59002`. If a second copy starts — e.g. the watchdog and the restart bat fire simultaneously — it cannot bind the port and exits immediately. The OS releases the binding on exit, even on a crash, so no stale lock files. Same implementation on Windows and Mac (`socket` module, already imported).

---

## v4.8

- **Message age filter** — messages whose timestamp is older than 3 minutes are silently skipped before being sent to Kokoro. Fixes a replay bug where switching to a recently-touched session file could cause old messages to be spoken aloud.

---

## v4.7

- **Scan interval 10s → 5s** — watcher now detects new Cowork sessions within 5 seconds instead of 10; halves worst-case delay when switching between open sessions
- **Default speed 1.1 → 1.2** — all installers now ship with `SPEED = 1.2`; existing installs unaffected (change live with `set_speed.py`)
- **State file pruning** — `tts_watcher_state.json` now evicts entries for transcripts older than 7 days on every save; prevents unbounded growth in long-running installs
- **Watcher log rotation** — `tts_watcher_log.txt` is now capped at 1 MB; when it exceeds that it is renamed to `tts_watcher_log.txt.prev` and a fresh log starts. Total log footprint stays under ~2 MB regardless of how long the watcher has been running. Same pattern as the watchdog's Kokoro log rotation.

---

## v4.6

- **Poll interval 0.5s → 0.1s** — watcher now checks for new transcript lines every 100ms instead of every 500ms; cuts worst-case delay between response finishing and speech starting from 500ms to 100ms, with negligible CPU cost

---

## v4.5

Ported three improvements from the separately-developed Codex TTS system:

- **Kokoro retry cooldown** — after a failed send, messages are skipped for 15 s instead of hammering a downed server on every poll cycle; cooldown clears automatically on recovery
- **Permission payload filter** — `should_skip_text()` drops JSON blobs containing permission-check keys (`outcome`, `risk_level`, `user_authorization`, `rationale`) before they reach Kokoro
- **Faster new-session detection** — `SCAN_INTERVAL` reduced from 30 s → 10 s → 5 s; new Cowork sessions are now picked up within 5 seconds

---

## v4.4

- **Replay bug fix** — added `tts_watcher_state.json` to persist per-transcript line positions; re-opening an existing session no longer replays old messages
- **3-step start decision** — known transcript → resume saved line; fresh file (< 60 s old) → read from start; stale file → skip to end
- **`seed_state.py`** — one-off migration helper to pre-populate state on first upgrade
- **Watchdog v2** — replaced blocking `TcpClient.Connect` with 2-second `BeginConnect` timeout; added 5-minute heartbeat log; Kokoro log rotation on restart

---

## v4.3

- Voice preview lineup reordered and timing improved (8 s gap between voices, up from 6 s)
- `MAX_CHARS` in `tts_server.py` increased from 3 000 to 5 000 — longer replies now speak in full

---

## v4.2

- **Ctrl+Alt+X instant stop** — replaced slow PowerShell shortcut (1–3 s startup overhead) with an in-process `GetAsyncKeyState` polling thread; response time < 100 ms

---

## v4.1

- **Windows MAX_PATH fix** — applied `\\?\` extended-length prefix to `SESSIONS_DIR` so `os.walk()` finds JSONL paths over 260 characters
- **Scan interval** — full directory scan throttled to every 30 s (previously ran on every 0.5 s poll)
- `followlinks=True` and `onerror` logging added to directory walk


