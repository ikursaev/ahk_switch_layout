# Keyboard Layout Switcher for AutoHotkey v2

An AutoHotkey v2 script that remaps CapsLock for seamless keyboard layout switching and fixes text typed in the wrong layout. Supports any combination of installed Windows keyboard layouts.

## Requirements

- Windows 10 (1607+) / 11
- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- A layout switch shortcut configured in Windows (Alt+Shift, Ctrl+Shift, or Win+Space)

The script auto-detects which shortcut you have configured. Win+Space is always available as a fallback.

## Installation

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Clone or download this repository
3. Run `main.ahk` — a tooltip will confirm detected layouts and the detected system hotkey
4. (Optional) Add a shortcut to `main.ahk` in your Startup folder (`shell:startup`) to run on login

To get a standalone `main.exe`, compile `main.ahk` with Ahk2Exe (included with AutoHotkey).

### Running as administrator

Without admin privileges, the script can't switch layouts or fix text in elevated apps (Task Manager, Registry Editor, installers, etc.). To enable full compatibility:

- Right-click `main.ahk` → Run as administrator, or
- Set `Config.RequestAdmin := true` in the script (the default) to auto-elevate on startup, or
- To start elevated at login without a UAC prompt every time, create a Task Scheduler task: trigger "At log on", action "Start a program" with `AutoHotkey64.exe` and the argument `"<path>\main.ahk"`, and tick "Run with highest privileges"

The startup tooltip warns you if the script is not running as admin.

## Hotkeys

| Hotkey | Action |
|--------|--------|
| `CapsLock` | Switch to the next keyboard layout |
| `Ctrl + CapsLock` | Fix the last word you typed (or the selected text) and switch to its layout |
| `Ctrl + Shift + CapsLock` | Fix everything typed since the cursor last moved (or the selected text) and switch to its layout |

CapsLock is permanently disabled (`SetCapsLockState "AlwaysOff"`).

## Fixing Text

Typed `ghbdtn` instead of `привет`? Press `Ctrl + CapsLock`.

- **Last word** — `Ctrl + CapsLock` deletes the word you just typed (plus any spaces after it) and pastes what the same keys type in the other layout. Keep holding `Ctrl` and press `CapsLock` again to convert back.
- **Whole phrase** — `Ctrl + Shift + CapsLock` does the same for everything typed since you last clicked, pressed Enter, moved the cursor or used a shortcut — for when you notice after a few words.
- **Selection** — when you haven't typed anything since the cursor moved, both hotkeys convert the selected text instead. `Ctrl + CapsLock` only does this when it saw you select text (dragging, double/triple-clicking or Shift+clicking over text, Shift+arrows, Ctrl+A); `Ctrl + Shift + CapsLock` always tries, for selections made some other way. With nothing selected, editors like VS Code copy the whole line, so a copied line is ignored unless the script saw it being selected.

Once you let go of `Ctrl`, the script switches to the layout the text was converted to, so you can keep typing. A tooltip shows the before/after result.

With three or more layouts, the target is the layout that changes the most characters — typing in English instead of Russian converts to Russian, not to German.

## How It Works

### Architecture

| Class | Responsibility |
|-------|----------------|
| `Config` | Timing constants, terminal shortcuts, the physical keys to map, and the admin elevation flag |
| `Layouts` | Layout detection, per-key character tables, system hotkey detection, and switching |
| `TypedKeys` | Records the physical keys typed since the cursor last moved, and whether text was just selected |
| `Converter` | Converts key sequences and text between layouts and picks the target layout |
| `Clip` | Clipboard save/restore, copying selections and pasting fixes |

### Layout Detection

On startup, the script calls `GetKeyboardLayoutList` to detect all installed layouts and asks Windows for each one's language name and code (e.g. `English (United States)`, `EN`), so every language works. Layouts are identified by their full keyboard layout handle, so two layouts of the same language (e.g. US and US-Dvorak) are kept apart (`EN-US`, `EN-US 2`).

Layouts added while the script runs are picked up the first time you type in them; added or removed layouts are also re-checked each time you fix text.

### Layout Switching

The script reads the registry (`HKCU\Keyboard Layout\Toggle`) to detect which system hotkey is configured, then always simulates that hotkey:

| Detected setting | Simulated keys |
|------------------|----------------|
| Alt+Shift (registry value `1`) | `Alt` + `Shift` |
| Ctrl+Shift (registry value `2`) | `Ctrl` + `Shift` |
| None / not found | `Win` + `Space` (always available on Windows 10/11) |

Alt+Shift and Ctrl+Shift only cycle between languages, so when two layouts share a language (e.g. US and US-Dvorak), the script uses `Win` + `Space`, which reaches every layout.

This works across all window types — regular Win32 apps, Electron apps (VS Code, Discord, Slack), UWP apps, shell windows, and terminals — because Windows itself handles the hotkey.

After pressing it, the script waits (up to 5 × 30ms) until the focused window reports the new layout. When fixing text, it presses the hotkey as many times as needed to reach the target layout, and not at all if it's already active. It waits until you let go of `Ctrl`: Windows answers a `Win` + `Space` pressed while `Ctrl` is held by reporting `Ctrl` as released, which would turn the next `Ctrl + CapsLock` into a plain `CapsLock` (and set off apps listening for `Ctrl` + `Win`, such as Wispr Flow).

### Character Mapping

For every installed layout, the script builds a table of what each physical key types, normal and shifted, using `MapVirtualKeyEx` and `ToUnicodeEx`:

- Covers the number row, all letter rows with their punctuation keys, the extra ISO key (`<>` on European keyboards), and Space
- Maps by physical position (scan code), so QWERTZ, AZERTY and Dvorak layouts convert correctly, not just Latin/Cyrillic pairs
- No hardcoded character tables — works with any layout combination

### Typed Key Tracking

An `InputHook` watches the keyboard (without blocking anything) and records each character key as a physical key plus the layout it was typed in. Backspace removes the last key. Clicking, arrows, Enter, Tab, shortcuts, or switching windows start over, since the typed keys may no longer end at the cursor.

Fixing a word then means pressing Backspace once per character and pasting what the same keys type in another layout. It pastes rather than types because Chromium-based apps (browsers, VS Code) type the English letters of simulated Unicode input as keys of the active layout, and the layout can't be switched first while `Ctrl` is held. Your clipboard is restored afterwards (see below), and it works in terminals too.

### Selection Conversion

For selected text, the script copies it, detects which layout it was typed in (each character votes for the layouts that can type it; ties go to the current layout), converts it key by key, and pastes the result. To undo, use the app's own undo (`Ctrl+Z`).

After any fix, the original clipboard is restored 400ms after pasting, so slow apps (Electron, Office) have time to read the converted text first. If you copy something else in the meantime, the restore is skipped.

### Terminal Awareness

In terminals, `Ctrl+C` sends an interrupt instead of copying, so fixing text uses each terminal's own shortcuts:

| Terminal | Copy | Paste |
|----------|------|-------|
| Windows Terminal | `Ctrl+Shift+C` | `Ctrl+Shift+V` |
| Classic console (cmd, PowerShell) | `Ctrl+Insert` | `Shift+Insert` |
| ConEmu / Cmder | `Ctrl+Shift+C` | `Ctrl+Shift+V` |
| Git Bash / MSYS2 (mintty) | `Ctrl+Insert` | `Shift+Insert` |
| Alacritty | `Ctrl+Shift+C` | `Ctrl+Shift+V` |
| WezTerm | `Ctrl+Shift+C` | `Ctrl+Shift+V` |
| Other apps | `Ctrl+C` | `Ctrl+V` |

Terminals can't replace a selection, so a converted selection is pasted at the cursor, and only single-line selections are accepted (a terminal would run every pasted line). To fix what you just typed at the prompt, use the last-word or whole-phrase hotkeys, which work in any terminal.

To add support for other terminals, add their window class to `Config.TerminalClasses`. VS Code's integrated terminal can't be told apart from the editor by window class, so select text there before using `Ctrl + Shift + CapsLock`.

## Configuration

All tunables are in the `Config` class at the top of `main.ahk`:

| Setting | Default | Description |
|---------|---------|-------------|
| `RequestAdmin` | `true` | Auto-request admin elevation on startup |
| `ClipboardWait` | `0.3` | ClipWait timeout when copying a selection (seconds) |
| `ClipboardRestoreDelay` | `400` | Delay before restoring the clipboard after pasting (ms) |
| `LayoutSwitchRetryDelay` | `30` | Delay between checks that a layout switch took effect (ms) |
| `LayoutSwitchMaxRetries` | `5` | Max checks per layout switch |
| `TooltipShort` | `1500` | Short tooltip duration (ms) |
| `TooltipMedium` | `3000` | Medium tooltip duration (ms) |
| `TooltipLong` | `4000` | Long tooltip duration (ms) |
| `MaxDisplayLength` | `20` | Max characters shown in tooltip |
| `MaxTypedKeys` | `200` | Max typed keys remembered for fixing |
| `TerminalClasses` | see above | Terminal window classes and their copy/paste shortcuts |

## Known Limitations

These cases cannot be solved by any AutoHotkey script:

- **Exclusive fullscreen games** — DirectInput bypasses the normal Windows input pipeline entirely
- **Remote Desktop / VM windows** — keystrokes are forwarded to the remote OS
- **Apps blocking clipboard** — fixing text won't work in apps that restrict clipboard access (password managers, some banking apps)

Fixing typed text relies on the script seeing every keystroke:

- Characters typed with AltGr or dead keys (`^` + `e` = `ê`) start a new word, since their output can't be predicted
- Autocomplete and autocorrect change text without keystrokes. In fields that complete inline (e.g. a browser's address bar), the first Backspace removes the suggestion and a stray character can remain — select the text and use `Ctrl + Shift + CapsLock` there
- Where letter keys are commands rather than typing (Vim's normal mode, single-key shortcuts on websites), the script still counts them as typed until the next click, arrow key or Enter

## Troubleshooting

**Layout doesn't switch:**
- If not running as admin, elevated apps (Task Manager, etc.) won't respond — see [Running as administrator](#running-as-administrator)

**`Ctrl + CapsLock` says "Nothing to fix":**
- You haven't typed anything since the cursor last moved, and the script didn't see you select text. Select it and press `Ctrl + Shift + CapsLock`

**Text conversion produces wrong results:**
- Selection conversion guesses which layout the text was typed in; it needs enough characters to tell
- Single characters may not convert correctly if they exist in multiple layouts

**Tooltip says "No conversion available":**
- The keys type the same characters in every other layout (e.g. digits or spaces only)
