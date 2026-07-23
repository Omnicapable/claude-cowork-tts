# Claude Cowork TTS - Changelog

## Shared panel v3.4z - Windows tray access polish

- **Windows installers now add an Omnicapable Voice tray icon.** The tray helper
  starts with Windows and gives users a visible notification-area icon for quick
  access.
- **The tray menu keeps the common actions close.** Users can open the UI,
  restart the local TTS server, or quit only the tray icon without changing the
  existing hotkeys, Desktop launcher, or server behavior.
- **The tray startup path is quoted for Windows profiles with spaces.** This keeps
  the tray helper reliable for users whose account folder contains spaces.

---
## Shared panel v3.4y - Mac installer access polish

- **Mac installers now open the panel once after install.** After the server and
  watcher checks finish, the installer launches `~/.claude/open_panel.sh` so the
  user immediately sees Omnicapable Voice.
- **Mac final instructions now list every access path.** The installer prints
  `Open panel: Ctrl+Option+Space`, the Desktop launcher path, and the
  Services / Quick Actions entry.

---
## Shared panel v3.4x - Final footer shortcut polish

- **Footer shortcut wording is now final.** The centered footer uses
 `Open: Ctrl+Alt+Space` on Windows and `Open: Ctrl+Option+Space` on macOS.
- **Footer breathing room was increased.** The gap between `Omnicapable Voice`
 and the Open shortcut line was increased so the centered footer reads cleaner.

---
## Shared panel v3.4w - Corner labels and type-box offset

- **Bottom-corner version labels are shorter.** The left corner now reads
 `UI: v3.4`; the right corner shows only the selected integration version
 (`v4.14`, `v1.8`, etc.) because the active chip already identifies the TTS UI.
- **Cowork and Claude Code type boxes sit slightly lower.** The non-Codex type
 box gained a small top offset while Codex keeps its existing compensated
 layout.

---
## Shared panel v3.4v - Footer version corners

- **Version labels moved to the bottom corners.** The shared UI version now sits
 in the bottom-left corner and the selected TTS integration version sits in the
 bottom-right corner, both with equal edge padding. The centered footer keeps
 only `Omnicapable Voice` and the platform-aware Open shortcut.

---
## Shared panel v3.4u - Footer spacing polish

- **Footer spacing now breathes more evenly.** The three footer lines are centered
 with equal row spacing, the version row is darker, and Codex gets a tuned footer
 offset so the footer group sits better in the space below the type box.

---
## Shared panel v3.4t - ASCII-clean speed suffix

- **The speed readout now uses plain `x`.** The previous multiply-symbol path
 could render as mojibake after Windows/PowerShell rewrites, so the panel now
 shows values like `1.20x` consistently.
- **Remaining mojibake dash sequences were normalized.** Comments, hover titles,
 and fallback text are ASCII-clean in the panel HTML.

---
## Shared panel v3.4s - Selected integration version footer

- **The footer now shows both the shared UI version and the selected integration version.**
 It reads like `UI v3.4 - Cowork v4.14`, `UI v3.4 - Codex v1.8`, or
 `UI v3.4 - Claude Code v3.4` depending on the selected chip. Cowork and Codex
 use their watcher versions; Claude Code falls back to the shared server version
 because it does not run through a separate watcher.

---
## Shared panel v3.4q - Open UI hint and lighter Speak glass

- **The footer now labels the open-panel shortcut.** Under TTS v3.4, the panel
 shows `(Open UI: Ctrl+Alt+Space)` on Windows and `(Open UI:
 Ctrl+Option+Space)` on macOS, using the same platform-aware detection as the
 replay and stop shortcut labels.
- **The frosted Speak button is less blurred.** The glass effect was softened so
 typed text remains more legible behind the corner button.

---
## Shared panel v3.4p - Hidden Windows hotkey launcher

- **Ctrl+Alt+Space no longer opens through a visible command prompt.** The
 Windows hotkey daemon now prefers Open-Panel.vbs via wscript.exe before
 falling back to the older batch path, avoiding the %USERPROFILE%\.claude>
 console prompt.
- **Desktop and Start Menu shortcuts use the same hidden launcher.** Shortcuts
 now target wscript.exe "...\Open-Panel.vbs" while preserving the
 Omnicapable icon.

---
## Shared panel v3.4o - Speak focus glow and official icon audit

- **The Speak button now joins the text-box focus glow.** When the type box is
 focused, the button border receives the same pale focus glow so the outline
 does not visually stop at the corner where the button sits.
- **Official Omnicapable logo assets were audited.** Canonical favicon.svg
 matches logo.svg, canonical favicon.ico matches panel.ico, live kokoro
 assets match canonical, repo src assets match canonical by SHA256, and all
 six installer embeds contain the exact canonical SVG and ICO payloads.

---
## Shared panel v3.4n - Final launcher polish

- **Repeated shortcut launches now stay single-instance.** Windows and Mac
 launchers close an existing native panel_app.py before opening the panel, so
 repeated desktop/menu launches do not leave duplicate native panel processes.
- **Browser fallback sizing matches the finalized native panel.** Fallback app
 windows now use the shorter 336 x 736 content height / about 352 x 774
 outer height instead of the older taller values.

---
## Shared panel v3.4m - Final footer trim and release check

- **The empty space below TTS v3.4 is now about half the previous remainder.**
 The native wrapper height is 352 x 774 on the checked Windows display, down
 from 352 x 782 after the first footer trim and 352 x 798 before footer
 trimming began.
- **Docking remains bottom-right and inside the work area.** The measured live
 panel remains fully visible with right/bottom screen padding preserved.
- **Final release checks passed.** Live panel/assets, canonical markers, repo
 source sync, all six installer embeds, Windows installer parsing, Python AST
 syntax, Mac LF/no-BOM checks, and the security-pattern scan pass for build

---
## Shared panel v3.4k - Monitor-aware native window docking

- **Windows desktop shortcut placement now docks inside the actual monitor work
 area.** The pywebview wrapper measures the real native window rectangle and
 places it at the bottom-right of the nearest usable screen area, preventing
 the down/right off-screen launch on scaled multi-monitor setups.
- **The panel remains native and branded.** The Windows taskbar/window icon
 still uses the Omnicapable icon, while raw Win32 positioning is now based on
 the measured native rectangle instead of mixed logical coordinates.
- **Release verification passed** for live panel assets, canonical markers,
 source sync, all six installer embeds, Python syntax, PowerShell installer
 parsing, and the security-pattern scan on the verified build.

---
## Shared panel v3.4i - Mute gate and real-logo favicon

- **Speak button corner alignment is now anchored to the text field itself.**
 The button lives inside the type-box frame, uses the same 10px radius, and
 keeps its right/bottom edges aligned with the type box in Cowork, Claude Code,
 and Codex modes. The textarea is block-level so the wrapper has no browser
 baseline gap under it.
- **Master mute is enforced by the shared server, not only the watchers.**
 Muting now immediately stops current speech and blocks direct text, replay,
 preview, and panel-speak requests at the final audio gate, including Codex
 traffic that reaches port 59001.
- **Favicon assets use the real Omnicapable logo.** The simplified black-square
 redraw was removed; favicon.svg now matches logo.svg, and the .ico
 files were regenerated from the original Omnicapable PNG.
- **Release verification was rerun after the final polish.** The live panel,
 favicon/logo assets, canonical build markers, repo source copies, installer
 embeds, Windows installer parsing, Python syntax, and security-pattern scan
 all pass for the verified build.
- **Installer embeds were cleaned for public release.** Windows and Mac icon
 asset blocks are singular and rerunnable syncs now replace those blocks
 instead of appending duplicates. Favicon/logo cache-busting URLs now use the
 current panel build slug. Mac shell scripts were normalized to LF-only with
 no BOM; Windows installers remain UTF-8 with BOM for PowerShell 5.1.

---
## Shared server v3.4h - Public release sync, native installers, polished panel

- **The GitHub repo sources and installer embeds are synced from the canonical
 TTS App Build panel.** src/panel.html, src/tts_server.py,
 src/panel_app.py, icon assets, and the Windows/Mac installer-embedded copies
 now match the live v3.4 panel/server/window build.
- **Fresh installs open the native mini-app by default.** All three Windows
 installers now install pywebview; all three Mac installers install
 pywebview plus the Cocoa/WebKit pyobjc packages needed by pywebview's
 native macOS backend. The browser app-window fallback remains in place.
- **Mac access is easier without shipping an unsigned .app.** Mac installers
 still create the Desktop Omnicapable Voice.command, and now also create a
 Services/Quick Action entry named Omnicapable Voice that runs
 ~/.claude/open_panel.sh. Users can assign it a keyboard shortcut from
 System Settings -> Keyboard -> Keyboard Shortcuts -> Services.
- **Panel polish after the design pass.** The top system chips, type box and
 Speak button share the large-circle gray; Replay/Stop/status positions were
 tuned across Cowork, Claude Code and Codex; Codex mode bulbs are softer; the
 clipboard button was removed; the placeholder is left-aligned; and the Speak
 button is fitted into the type box corner with the same 10px radius.
- **Icons are public-release ready.** The panel serves a vector favicon.svg
 first, with .ico fallback, and the server now strips cache-busting query
 strings before routing static assets so favicon/logo URLs resolve correctly.

---
## Shared server v3.4g - Speak box: buttons below the field

- **The speak box was restructured so the two fixes actually hold.** While the
 buttons overlapped the field's corner (the "notch"), the field's scrollbar
 physically spanned the full height behind them and the focus glow bled around
 all four edges - neither could be cleanly removed no matter how it was offset.
 The buttons now sit in a row BELOW the text field:
 - the field's scrollbar ends exactly at the field's own bottom edge, right
 above the buttons - never behind them;
 - the focus glow is a gentle pale-white halo around the field only, with
 nothing below or beside it to bleed onto.

---

## Shared server v3.4f - Notch restored, scrollbar capped at the notch

- **The speak-box notch is back to a clean straight L.** The previous scrollbar
 fix inset the buttons 12px, which bent the notch seam and let the scrollbar run
 full height beside them. The buttons are flush to the corner again, so the seam
 is a straight top + left line.
- **The scrollbar now ends at the notch.** Being opaque, the button cluster caps
 the bar: it is visible from the top of the field down to the cluster's top edge
 and covered below, so it reads as ending exactly at the notch top rather than
 running down past it.
- **No glow under the buttons.** The focus glow is pulled up-and-left and the
 buttons are opaque, so the area behind and below them stays plain gray - only
 the notch seam lights up.

---

## Shared server v3.4e - Scrollbar clear of buttons, glow off the corner, 8px radii

- **The speak-box scrollbar no longer hides behind the buttons.** A stable
 scrollbar gutter is reserved at the far right and the button cluster is inset
 to its left, so the bar runs in its own clear column instead of being covered
 by the buttons at the bottom.
- **Focus glow stays off the bottom-right corner.** The field's pale glow is now
 pulled up and to the left, so it no longer haloes the corner where the buttons
 sit - down there only the notch seam lights up.
- **Inner corner radius bumped 5px -> 8px.** 5px was too subtle to read against
 the pill curve beside it; 8px is clearly rounded and unified across the voice
 dropdown and the flat edges of the arrow / Preview buttons.

---

## Shared server v3.4d - Corner dock, unified focus glow, Codex parity

- **Scrollbars restyled.** The voice dropdown and the speak box used the bright
 default white scrollbar, which jarred against the dark UI. They now show a thin
 muted-gray thumb (transparent track, rounded, inset) that reads as part of the
 panel. Covered for both platforms: `::-webkit-scrollbar` styles WebView2 on
 Windows and WebKit on macOS, with `scrollbar-color` as a Gecko fallback.
- **Opens straight into the bottom-right corner, no flash.** The native window is
 now created hidden, positioned and branded, then shown - so it appears once, in
 place, instead of opening at a default spot and jumping. It docks to the
 bottom-right corner of the work area with a 14px buffer on both edges, clamped
 so no part ever leaves the screen. (The Edge/Brave fallback got the same
 bottom-right target.)
- **Codex mode buttons match the others.** Final Replies / Final + Thinking were
 36px tall (9px padding) while Preview / Preview all are 31px, which made the
 Codex view feel inconsistent. They are now 31px too. The row was already full
 width - it only ever looked narrower because the buttons were a different size.
- **The speak-box focus glow is now one continuous outline.** When you click into
 the text area, the notch seam (the button cluster's top and left edges) picks
 up the same pale-white glow as the field, so the whole shape reads as a single
 lit edge. The buttons stay opaque, so the field's glow is never visible through
 them.

---

## Shared server v3.4c - Softer focus, framed notch

- **Gentle focus glow on the speak box.** Clicking into the text area used to
 draw the hard 2px accent outline the other inputs use. It now gets a soft
 pale-white glow (a faint white border plus a low-opacity white halo) instead -
 quieter for the one control people type into most.
- **The button notch reads as part of the field.** The clipboard/Speak cluster
 is notched into the text area's bottom-right corner; it now carries a 1px
 border on its top and left edges, continuing the text area's own frame so the
 two look like one continuous outline. Its inner corner uses the same 10px
 radius as the text area, so the curves match rather than one being sharper.
- **Extra breathing room** below the speak box before the wordmark.

---

## Shared server v3.4b - Branded window, any-Chromium fallback, notched speak box

- **The window wears the Omnicapable mark.** pywebview has no icon option for
 its Windows backend, so `panel_app.py` pushes `panel.ico` onto the native
 window handle with `WM_SETICON` - the same icon the desktop shortcut uses, so
 the taskbar, the title bar and the shortcut all match. Previously the window
 showed pywebview's default mark. (macOS takes its icon from an application
 bundle rather than the window, so that platform still needs a packaged `.app`;
 the call is a no-op there rather than an error.)
- **The browser fallback is no longer Edge-only.** Plenty of people run Brave
 and have no Edge at all. The launcher now walks a list - Brave, Chrome, Edge,
 Vivaldi, Opera, Chromium, in that order, across per-user and per-machine
 install paths - and uses the first it finds, falling through to the default
 browser if none match. Any Chromium browser can host the panel as a chromeless
 app window, so nothing else had to change.
- **Speak box: the text area fills the card.** It now runs the full width and up
 over the space above the buttons, so the only framed element is the button
 cluster itself, which is painted in the card colour and sits over the text
 area's bottom-right corner - reading as a notch cut out of it. Typed text stays
 clear of the buttons via bottom padding, while lines above them run full width.
- **Corner radii unified inside the dial.** The voice dropdown went from 8px to
 5px (35% less round), and that same `--r-inner` now applies to every square
 corner in the circle: the flat inner edges of both arrow buttons and of
 Preview / Preview all. One variable controls all five.
- **Spacing.** +8px between the logo and the system chips, the same +8px between
 the chips and the SPEED readout, and +8px between the speak box and the
 wordmark. Measured: 24px / 23px / 14px.
- Replay and Stop dropped 14px, easing their lift from -46px to -32px.

---

## Shared server v3.4a - Spherical controls, wider window, native mini-app

**Interface**

- **Replay and Stop are spheres.** Both are 58px pale 3D orbs with the glyph and
 label stacked inside, sitting directly on the page - there is no card behind
 them. They are pushed out toward the edges, centred at 17% and 83% of the panel
 width. The volume readout keeps its own centred row directly under the dial,
 and the orbs are pulled up over that row so they tuck into the empty bottom
 corners either side of it - the readout is centred and the orbs are at the far
 edges, leaving 32px clear on each side. This is safe because the volume arc
 curves away from those corners: at the orbs' x position it sits 30px higher, so
 nothing is covered and the slider's grab area is untouched. Lifting them also
 raised everything underneath, including the speak box. Size and
 placement were measured off a marked-up screenshot rather than guessed. The
 hints stay platform-aware: `Ctrl+Alt+R` / `Ctrl+Alt+X` on Windows,
 `Ctrl+Option+R` / `Ctrl+Option+X` on macOS.
- **Speak box is now a compose area.** The single-line input became a
 multi-line textarea filling the card, with the clipboard and Speak buttons
 right-aligned beneath it. Enter speaks; Shift+Enter starts a new line.
- **Control sizes tightened.** The Set orb is 46px (was 62) and the Replay/Stop
 orbs are 58px (was 72). The buffer between the shortcut hints and the box
 below them went from 6px to 18px.
- **Set is a sphere too,** 46px, centred in the dial with 29px of clearance
 from the inner circle, so it never crowds the arcs.
- **Stop glows pale red whenever anything is speaking,** and stops glowing the
 moment audio ends. Stop has always been global - it stops the single shared
 output stream - so it correctly lights up and works no matter which system
 chip you happen to be viewing. It deliberately does NOT glow while muted.
- **Set glows amber while your chosen voice is not the active one,** including
 after an audition, so it is obvious the choice still has to be committed.
 Speed and volume are excluded on purpose: they apply the instant you release
 the dial, so implying they need committing would be untrue.
- **The voice line reads "Claude's Voice:"** for the Claude Code slot. The chip
 still says "Claude Code" - that is the product; the voice line is about whose
 voice it is.
- **Window is 20% larger:** the body is now 336px and the window opens at a
 337x710 viewport, which fits the tallest panel state (699px, Codex with its
 reading-mode row) with no scrolling in any state.

**Fixed: the window opened in one place and then jumped to another.**
`pywebview` was never actually installed, so the launcher always fell back to an
Edge `--app` window. Edge restores its previous bounds and cascades every launch
after the first, ignoring `--window-size` and `--window-position` - so the window
opened wrong and was then visibly corrected. The panel now opens as a real
native mini-app window that computes its size and position *before* the window
is created, so nothing moves after it is painted. It is also no longer a browser
window at all: no tabs, no address bar, and its own taskbar entry, so it cannot
get lost among other browser tabs.

Two notes for the fallback, which still matters for anyone without `pywebview`:
it now uses a dedicated `--user-data-dir`, clears Edge's remembered bounds before
each launch, and `Position-Panel.ps1` re-docks the window deterministically -
deriving the frame thickness from the window itself so it is correct at any DPI.
`panel_app.py` deliberately does not enable DPI awareness: doing so reports
physical pixels (2560x1528 rather than 1707x1019 on a 150% display) while
pywebview's coordinates are logical, which would open the window at about two
thirds of its intended size.

---

## Shared server v3.4 - Per-system voice and speed

**Each TTS system can now have its own voice and its own speed**

- **Voice and speed are per-system.** Cowork can read in one voice at one speed
 while Codex uses another. The chips already implied this separation; now it is
 real. Pick a system's chip, choose a voice or move the Speed arc, and that
 choice applies to that system only.
- **Volume and the master mute stay global.** There is one output stream and one
 master switch, so scoping those would be a lie. They are deliberately unscoped.
- **Settings live in one server-owned file,** `~/.claude/tts_systems.json`. They
 survive a restart of the server *and* of any watcher. Watchers hold no settings
 of their own, so there is nothing to push to them and nothing to reload - they
 only tag what they send.
- **Nothing is stored until you choose it.** A system with no pinned voice or
 speed inherits the global default, so a fresh install behaves exactly as before.
- **Single-system installs are unchanged.** With fewer than two systems present
 the chip row stays hidden and the panel writes the global default, exactly as
 every earlier version did - so `set_voice.py` / `set_speed.py` and the panel
 never disagree on a one-pack machine.

**Wire format** - the v2.1 `VOICE=` prefix became a repeatable header:

```
SYS=cowork|text
VOICE=af_bella|SPEED=1.4|text
text <- untagged; unchanged behaviour
```

Resolution per utterance: a `SYS`-tagged sender uses its stored panel setting,
then the wire tag, then the global default; an untagged sender uses the wire tag
then the global. The stored setting deliberately outranks a `VOICE=` tag for a
tagged sender - that tag is how a watcher emits a hand-edited `WATCHER_VOICE`,
and a voice picked in the panel must never be silently overridden by a constant
someone set months ago. Senders with no `SYS` have no stored setting, so
"explicit wins" still holds for every ad-hoc caller.

- **Claude Code needs no watcher change.** It speaks through a Stop hook that
 sends bare text and cannot tag itself, so untagged input resolves to the
 `claude_code` slot whenever that hook is installed. This works on every
 existing install without anyone re-running an installer.
- **Speed is captured once per utterance,** never re-read per chunk, so changing
 it mid-reply cannot shift tempo between chunks of the same sentence. Playback
 still uses the single continuous `OutputStream` - no per-sentence gaps.
- **Previews use the speed the dial is showing,** even mid-drag and even when it
 differs from the global, so an audition is always what you are about to get.
- **The live dot follows the audio, not the view.** The server reports which
 system is speaking and the panel puts the indicator on that chip, so viewing
 Codex while Cowork talks no longer implies the audio belongs to Codex.

**Fixed: a tagged control command could be spoken aloud.** `__STOP__` and friends
were matched *before* the prefix parser ran, so `SYS=cowork|__STOP__` fell through
and was read out as literal text instead of stopping playback. Headers are now
stripped first.

**Fixed: rapid Speed/Volume nudges landed on the wrong value.** The 2-second poll
overwrote the dial between keypresses, so four PageUp presses moved 0.30 instead
of 0.40. A local edit now holds for 2.5s before polled state can overwrite it;
switching chips still retargets the dials immediately.

- **Fixed: the panel window opened far too large.** `pywebview` was never
 installed, so the launcher always fell back to an Edge `--app` window - and
 Edge restores its previous bounds and cascades on every launch after the
 first, ignoring both `--window-size` and `--window-position`. The result was a
 ~840x1000 window wrapped around a 280px panel, drifting further off-screen each
 time. The fallback now uses a dedicated `--user-data-dir`, and a small
 `Position-Panel.ps1` re-docks the window deterministically after launch: it
 derives the frame thickness from the window itself (so it is correct at any
 DPI), sets the web viewport to exactly 280px, clamps the height, and pins it
 flush to the right edge. Measured result: 295x666 outer, 280px viewport, zero
 horizontal dead space. Installing `pywebview` still gives the nicer chromeless
 window; this makes the fallback behave correctly for everyone who has not.

**Panel:** now 280px wide and docked to the right edge of the work area on both
Windows and macOS. The dial fills the full content width instead of floating in
~38px of dead space. 272px is the hard floor - below that the button rows overflow.

---

## Shared server v3.3 - Multi-system chips

**The panel now knows which TTS packs are actually installed**

- **System chips are real.** The panel always drew a single tab labelled
 "Claude Code", whichever pack you had installed - the Cowork and Codex chips
 depended on status endpoints that were never built. Both watchers now serve a
 loopback-only status API, and the panel shows a chip per system it can
 actually see.
 - Cowork watcher - `127.0.0.1:59011`
 - Codex watcher - `127.0.0.1:59012`
 - `GET /state` reports system, version, mode and last spoken text;
 `POST /replay` re-speaks that system's last message; Codex also accepts
 `POST /mode` to switch between Final Replies and Final + Thinking.
 These are bound to 127.0.0.1 and are unreachable from the network. They do not
 touch the existing single-instance UDP locks on 59002 / 59003, and a port
 clash is logged and ignored rather than stopping the watcher.
- **Claude Code detection.** That pack has no watcher - it speaks through a Stop
 hook - so the server reports whether `tts_hook.ps1` / `tts_hook.sh` exists and
 the panel offers the chip only then.
- **Single-system installs hide the chip row.** With one system there is nothing
 to switch between, so the row is dropped instead of showing one dead tab.
- **Per-system Replay and the Codex mode toggle now work.** Both were written
 but unreachable, since no chip could ever become active.
- **Chips are keyboard operable** (Tab to focus, Enter or Space to select).

### Panel appearance
- Selected voice shows the name only ("Onyx"); the accent and gender stay in the
 picker where they help you choose.
- Shortcut hints under Replay and Stop, labelled for the host platform:
 Ctrl+Alt+R / Ctrl+Alt+X on Windows, Ctrl+Option+R / Ctrl+Option+X on macOS.
 These are the hotkeys the daemon already registered - the panel only labels
 them.
- The window opens phone-sized (352 - 600, capped at 660 tall) instead of
 sprawling to 380 - 900.
- Quieter greys throughout, chevron arrows drawn as SVG so they centre exactly,
 and a darker fill on the speak box.

### Watcher
- `tts_watcher.py` v4.12 - adds the panel status endpoint on 59011.

## Shared server v3.2 - Control panel

**A desktop panel for voice, speed, volume, replay and previews**

- **New control panel.** The server now serves a small local UI on
 `127.0.0.1:59010` (loopback only). It covers voice selection with previews,
 speed, volume, replay, stop, a mute switch, and a box for speaking arbitrary
 text. Open it from the Start Menu shortcut, `Open-Panel.bat`, or
 `open_panel.sh`. Shipped identically in all three Omnicapable Voice repos.
- **Per-TTS volume.** Previously there was no volume control at all - the only
 option was the system mixer, which affected everything. Volume is now applied
 to the speech itself and persists across restarts.
- **Optional native window.** With `pywebview` installed the panel opens as a
 real desktop mini-app (no browser chrome). `--top` keeps it above other windows.
- **Gapless playback, belt and braces.** In addition to the v2.4 clause chunking
 and v2.6 priority boost, playback now writes every chunk into a single
 continuous audio stream, so the output device is never stopped and restarted
 between chunks.
- **Faster previews.** Starting a preview interrupts whatever is playing instead
 of queueing behind it, so stepping through voices responds immediately.
- **Live state.** The server reports whether it is speaking and which voice is
 being auditioned, so the panel follows "Preview all" voice by voice.
- **Accessibility.** All panel controls are keyboard operable and screen-reader
 labelled.
- **Fix:** money amounts like `$50` were read as "5 dollars 0" - the pattern only
 matched the first digit. Now "50 dollars"; `$1,299` and `$9.99` also correct.
- **Fix:** the Codex Windows installer was UTF-8 *without* a BOM while containing
 non-ASCII characters, which PowerShell 5.1 misparses. BOM added.
- **Testing:** the server accepts `--mock`, which runs the full HTTP API with no
 audio hardware or model files - useful for CI and for debugging the UI.

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
 expanded - their patterns ended in a word boundary that cannot match before a space, so the
 rules existed but never fired. They now read "for example", "that is", "versus",
 "etcetera", "approximately".
- **Money reads naturally in more shapes.** `$3.5` reads "3 dollars and 50 cents" (the
 ".5" used to be left dangling after "3 dollars"), `$0.99` reads "99 cents", `$1.5 million`
 and `$1.5M` read "1 point 5 million dollars" (scale words thousand/million/billion/trillion
 plus attached suffixes k/M/B), and odd precision like `$12.345` falls back to
 "12 point 345 dollars". `$3.50` and `$1,234.56` read exactly as before.
- **More emoji and symbols stripped.** The star/symbol and arrow blocks (U+2B00-2BFF,
 U+2190-21FF - e.g. star and left-right-arrow glyphs) no longer reach the voice.

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
 Money is unaffected - `$3.50` still reads "3 dollars and 50 cents". The pronunciation rule
 is deliberately ordered **after** the money rule: a ` point ` substitution applied first
 eats the decimal and produces "3 dollars point 50". That ordering is load-bearing and is
 pinned by a comment in `clean_text()`; do not move it above the money rule.

**Fixed / consolidated**

- **All installers now ship one identical Kokoro server.** Every installer writes the *same*
 file (`~/.claude/kokoro/tts_server.py`, port 59001), but the six embedded copies had drifted
 (six copies ranging from 170 to 192 lines), so **install order silently decided which server
 you ended up with** - installing a second product could silently replace a newer server with
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
- **Note - `tts_speak.py` is vestigial.** The installers still write it and still set
 `$ttsScript` / `TTS_SCRIPT` to it, but nothing invokes it: the variable is assigned once and
 never used. The "exactly one audio path" guarantee holds. The dead file and variable are
 safe to remove in a later pass.

**Known issue (not fixed here)**

- **Occasional silence mid-reply.** Synthesis and playback already overlap (a producer thread
 synthesizes ahead of the playback loop), so this is *not* a serialization problem. Two real
 causes remain: playback calls `sd.play()`/`sd.wait()` per chunk, which opens and closes an
 output stream for every chunk; and there is no buffer-ahead, so playback starts the instant
 chunk 1 is ready and any slower chunk becomes an audible gap. The synthesis queue is also
 unbounded. Being addressed separately - it touches stop-hotkey semantics and interacts with
 `_refresh_audio_device()`, so it is deliberately not bundled with this release.

---

## v4.14 (current)

- **Cowork now has its own voice and speed.** Every utterance is tagged
 `SYS=cowork|` so the shared server applies the voice and speed you picked for
 Cowork in the panel. The watcher stores no settings itself - they live in
 `~/.claude/tts_systems.json` - so a setting change needs no reload here and a
 watcher restart cannot lose one. Requires shared server v3.4+; older servers
 ignore the tag and fall back to the global voice, so a mixed install still speaks.
- **`WATCHER_VOICE` is now a fallback, not an override.** If you pick a Cowork
 voice in the panel, the panel wins. The constant is kept so existing hand-edited
 installs keep working untouched, and `Restart-Server.ps1` now carries a hand-set
 value across an update instead of silently reverting it.
- **Fixed: the watcher could never work on macOS.** `SESSIONS_DIR` was built from
 `%APPDATA%` with a hardcoded Windows fallback (`~\AppData\Roaming`), so on a Mac
 it scanned a path that cannot exist and silently never spoke. It now resolves
 `~/Library/Application Support/Claude/local-agent-mode-sessions` on macOS, the
 XDG location on Linux, and `%APPDATA%` on Windows; `TTS_SESSIONS_DIR` overrides
 all three. (This fix was described under v4.13 but was never actually present
 in the source.)
- **Fixed: the stop-hotkey poller crashed on macOS.** `_hotkey_poller` called
 `ctypes.windll` unguarded, so setting `TTS_ENABLE_GLOBAL_HOTKEY=1` on a Mac threw
 in a background thread. It now returns early off Windows, matching Codex TTS.
- **Control commands are never tagged.** `__STOP__` and friends are instructions,
 not utterances, so they are sent untagged and cannot be mistaken for speech.

---

## v4.13

- **Mac stop hotkey needs no permission now.** The macOS stop hotkey (Ctrl+Option+X) was rewritten from `pynput` to Carbon `RegisterEventHotKey`, which is not gated by Accessibility / Input Monitoring, so there is no first-use permission prompt. The leftover Automator "Stop TTS" service was removed and `pynput` dropped from the Mac dependencies.
- **Fixed the Mac hotkey failing to start.** On macOS 11+, `ctypes.util.find_library("Carbon")` returns `None` (system frameworks live in the dyld shared cache), so the daemon crashed before registering. It now loads Carbon by absolute path and logs any startup error to `~/.claude/tts_hotkey.log`.
- **Replay the last answer.** New global hotkey - Ctrl+Alt+R (Windows) / Ctrl+Option+R (macOS) - re-speaks the last reply. The shared server stores the last text and handles a new `__REPLAY__` command.
- **Audio follows your output device.** The server refreshes the audio device before each utterance, so switching output (e.g. connecting AirPods or headphones) is picked up without restarting the server.
- **Clearer install docs.** The README manual-install steps now include the full `git clone` + `cd` sequence (with a ZIP fallback), and the Controls list documents stop, replay, speed, voice change, and voice previews.
- **Mac installer fixes (from a Mac install report).** Removed the UTF-8 BOM that broke `./install_cowork_tts_Mac.sh` (the BOM hid the shebang); fixed an empty-string command (`"" >` - `: >`) that aborted the install under `set -e` right before the final step; and the Cowork session watcher now resolves the macOS app-data path (`~/Library/Application Support/Claude/local-agent-mode-sessions`) instead of a hardcoded Windows path, so it can find Cowork transcripts on Mac.
- **Overlapping / looping speech eliminated structurally (reported from a Mac session).** Root cause: two things could produce audio - the persistent server (which serialises requests and honours stop) and a one-off fallback (`tts_speak.py`) that did neither - so when the Stop hook misjudged a busy server as dead, it started a second, independent, **unstoppable** voice. The hook (Mac + Windows) now has **exactly one audio path**: it sends to the single server and, if the server is busy or still booting (~10s), **waits and retries for up to ~60s** rather than ever synthesising directly. Worst case is a short delay; overlapping or uncancellable audio is now structurally impossible.
- **Audio-device follow made non-fragile.** The output-device refresh no longer tears down and re-initialises PortAudio before every utterance (which caused macOS `PaMacCore -50` errors); it only re-scans after an idle gap, so it still follows AirPods/headphone switches without thrashing the audio backend mid-burst.
- **Fallback can no longer play unstoppable audio (Mac + Windows).** When the server was briefly unreachable, the Stop hook used to synthesise directly via `tts_speak.py` - a separate process with no socket and no stop handling, so Ctrl+Option+X / Ctrl+Alt+X could not cancel it. The hook now only ever plays through the server (starting it if needed and retrying); if the server still isn't ready it drops that one utterance rather than speaking through an uncontrollable path.
- **Voice preview: fixed samples playing in the wrong voice.** The preview announced each voice by mutating a shared global (`__VOICE:name__`) and sent the sample as a separate message - but synthesis runs on a background thread, so a fast preview could synthesise a sample *after* the next voice-switch had overwritten the global, playing it in the wrong voice (mismatched label/gender). Each sample now carries its own voice atomically via the per-request `VOICE=name|text` prefix, correct regardless of timing.
- **Install no longer blocked by Homebrew Python (PEP 668).** On macOS with Homebrew's Python, a global `pip install` is refused (externally-managed environment), which aborted setup at the package step. The installer now retries with `--break-system-packages` when it hits this, so it completes.
- **Money and large numbers now read correctly.** The `$` cleaner only handled a single digit and the thousands-comma strip only removed one comma per number, so `$50` was spoken "5 dollars zero" and `1,000,000` became "one thousand, zero zero zero". Both now parse the whole value: `$50` - "50 dollars", `$3.50` - "3 dollars and 50 cents", `1,000,000` - "1000000", `$1,234.56` - "1234 dollars and 56 cents". Plain decimals (`3.14`) and percentages were already correct and are unaffected.

---

## v4.12

- **Friendly Cowork preview commands.** Installers now write bundled `tts_preview.py`; the Cowork queue watcher routes both friendly queue text (`quick preview voices`, `preview all voices`, `preview voice onyx`) and legacy `__PREVIEW_*` tokens through it. Unknown queue text is logged and ignored instead of spoken.
- **Ctrl+Alt+X now actually ships.** Installers previously advertised the stop hotkey but
 installed it disabled (`TTS_ENABLE_GLOBAL_HOTKEY` off). The Windows installer now installs a
 standalone `tts_hotkey.py` (Windows `RegisterHotKey`, no low-level keyboard hook) and the Mac
 installer a `pynput` launchd agent (Ctrl+Option+X). Both auto-start at login, are single-instance
 (mutex / launchd label), and send `__STOP__` to the shared server. macOS additionally requires
 Accessibility permission - the installer prints exactly how to grant it.
- **`restart_tts_watcher.bat` no longer cross-kills Codex.** Its kill filter matched the substring
 `tts_watcher`, which also matched Codex's `codex_tts_watcher.py`. Narrowed to `\tts_watcher.py`
 so it stops only the Cowork watcher. Fixed in both the installer-generated bat and the live copy.

---

## v4.11

- **Age filter field-name fix** - the v4.8 message age filter (`MESSAGE_MAX_AGE_SECONDS = 180`)
 was a silent no-op. It read the timestamp from a field named `ts`, but Claude session
 transcripts store the time in an ISO-8601 field named `timestamp` (e.g.
 `"<timestamp>"`). Because `ts` was always absent, the `if ts is not None` guard
 skipped the whole check - no message was ever judged stale. This let a burst of 4-day-old
 replies get spoken when the watcher started on a session file with no saved position. **Fix:**
 the filter now reads the ISO-8601 `timestamp` field (parsed via `datetime.fromisoformat`) and
 still accepts a numeric epoch `ts` for backward compatibility. Verified: a 4-day-old message is
 skipped, a current one passes. Applied to `tts_watcher.py` and the embedded watcher in both the
 Windows and Mac installers. Codex TTS was audited and already reads `timestamp` (no change);
 Claude Code TTS is hook-based and cannot replay, so it is unaffected.
- **Live install reconciled** - the running setup had drifted to v4.9 and was missing the v4.10
 per-watcher-voice feature. v4.10 was back-ported into the live `tts_watcher.py` (`WATCHER_VOICE`
 + `VOICE=name|text` send), and the live shared server (`%USERPROFILE%\.claude\kokoro\tts_server.py`)
 was bumped **v2.0 - v2.1** to parse the per-request voice prefix. Change is additive: plain text
 is unaffected, so CLI and Codex TTS behave exactly as before. Verified end-to-end - a
 `VOICE=af_bella| - ` request spoke in that voice and left the global voice unchanged.

---

## v4.10

- **Per-watcher voice** - `WATCHER_VOICE = None` constant added to `tts_watcher.py`. Set it to
 any Kokoro voice name (e.g. `"am_onyx"`) to give Cowork TTS its own distinct voice, independent
 of Codex TTS or Claude Code TTS. Uses the `VOICE=name|text` per-request prefix protocol in
 `tts_server.py v2.1` - voice travels with each request, zero race conditions when multiple
 watchers are active simultaneously. Default `None` preserves existing behaviour.
- **Robust Python launcher (Windows)** - the installer, the auto-start launchers, the generated watchdog, and `watchdog.ps1` now invoke Python through the Windows `py -3` launcher instead of bare `python`. `py -3` is PATH-order independent and version-aware, so on machines with more than one Python install the watcher and Kokoro server always start under Python 3.x - fixing silent failures when bare `python` resolved to an unexpected interpreter. `watchdog.ps1` resolves a concrete interpreter path at startup and falls back to `python`/`python3` if the launcher is absent. Process detection (`Get-Process python`) is unchanged. **Mac is unaffected** - its installer already resolves `python3` once into `$PYTHON` and reuses it everywhere.

---

## v4.9

- **Single-instance lock** - on startup the watcher binds a UDP socket to `127.0.0.1:59002`. If a second copy starts - e.g. the watchdog and the restart bat fire simultaneously - it cannot bind the port and exits immediately. The OS releases the binding on exit, even on a crash, so no stale lock files. Same implementation on Windows and Mac (`socket` module, already imported).

---

## v4.8

- **Message age filter** - messages whose timestamp is older than 3 minutes are silently skipped before being sent to Kokoro. Fixes a replay bug where switching to a recently-touched session file could cause old messages to be spoken aloud.

---

## v4.7

- **Scan interval 10s - 5s** - watcher now detects new Cowork sessions within 5 seconds instead of 10; halves worst-case delay when switching between open sessions
- **Default speed 1.1 - 1.2** - all installers now ship with `SPEED = 1.2`; existing installs unaffected (change live with `set_speed.py`)
- **State file pruning** - `tts_watcher_state.json` now evicts entries for transcripts older than 7 days on every save; prevents unbounded growth in long-running installs
- **Watcher log rotation** - `tts_watcher_log.txt` is now capped at 1 MB; when it exceeds that it is renamed to `tts_watcher_log.txt.prev` and a fresh log starts. Total log footprint stays under ~2 MB regardless of how long the watcher has been running. Same pattern as the watchdog's Kokoro log rotation.

---

## v4.6

- **Poll interval 0.5s - 0.1s** - watcher now checks for new transcript lines every 100ms instead of every 500ms; cuts worst-case delay between response finishing and speech starting from 500ms to 100ms, with negligible CPU cost

---

## v4.5

Ported three improvements from the separately-developed Codex TTS system:

- **Kokoro retry cooldown** - after a failed send, messages are skipped for 15 s instead of hammering a downed server on every poll cycle; cooldown clears automatically on recovery
- **Permission payload filter** - `should_skip_text()` drops JSON blobs containing permission-check keys (`outcome`, `risk_level`, `user_authorization`, `rationale`) before they reach Kokoro
- **Faster new-session detection** - `SCAN_INTERVAL` reduced from 30 s - 10 s - 5 s; new Cowork sessions are now picked up within 5 seconds

---

## v4.4

- **Replay bug fix** - added `tts_watcher_state.json` to persist per-transcript line positions; re-opening an existing session no longer replays old messages
- **3-step start decision** - known transcript - resume saved line; fresh file (< 60 s old) - read from start; stale file - skip to end
- **`seed_state.py`** - one-off migration helper to pre-populate state on first upgrade
- **Watchdog v2** - replaced blocking `TcpClient.Connect` with 2-second `BeginConnect` timeout; added 5-minute heartbeat log; Kokoro log rotation on restart

---

## v4.3

- Voice preview lineup reordered and timing improved (8 s gap between voices, up from 6 s)
- `MAX_CHARS` in `tts_server.py` increased from 3 000 to 5 000 - longer replies now speak in full

---

## v4.2

- **Ctrl+Alt+X instant stop** - replaced slow PowerShell shortcut (1 - 3 s startup overhead) with an in-process `GetAsyncKeyState` polling thread; response time < 100 ms

---

## v4.1

- **Windows MAX_PATH fix** - applied `\\?\` extended-length prefix to `SESSIONS_DIR` so `os.walk()` finds JSONL paths over 260 characters
- **Scan interval** - full directory scan throttled to every 30 s (previously ran on every 0.5 s poll)
- `followlinks=True` and `onerror` logging added to directory walk
## Open-panel global hotkey polish
- Added automatic open-panel hotkeys to the existing no-extra-permission hotkey daemons: Ctrl+Alt+Space on Windows and Ctrl+Option+Space on macOS.
- Kept the existing stop/replay shortcuts unchanged: Ctrl+Alt+X/R on Windows and Ctrl+Option+X/R on macOS.
- Confirmed the Mac installer still installs the Omnicapable Voice Quick Action under ~/Library/Services for Services/Quick Actions access without a .app bundle.















