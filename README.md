# Keyboard Layout Switcher for AutoHotkey v2

An AutoHotkey v2 script that remaps CapsLock for seamless keyboard layout switching and automatic text conversion between layouts. Supports any combination of installed Windows keyboard layouts.

## Requirements

- Windows 10/11
- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- A layout switch shortcut configured in Windows (Alt+Shift, Ctrl+Shift, or Win+Space)

The script auto-detects which shortcut you have configured. Win+Space is always available as a fallback.

## Installation

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Clone or download this repository
3. Run `main.ahk` — a tooltip will confirm detected layouts and the detected system hotkey
4. (Optional) Add a shortcut to `main.ahk` in your Startup folder (`shell:startup`) to run on login

A precompiled `main.exe` is also included if you prefer not to install AutoHotkey.

### Running as administrator

Without admin privileges, layout switching won't work in elevated apps (Task Manager, Registry Editor, installers, etc.). To enable full compatibility:

- Right-click `main.ahk` → Run as administrator, or
- Set `Config.RequestAdmin := true` in the script to auto-elevate on startup, or
- Set "Run as administrator" on your Startup folder shortcut

The startup tooltip warns you if the script is not running as admin.

## Hotkeys

| Hotkey | Action |
|--------|--------|
| `CapsLock` | Switch to the next keyboard layout |
| `Ctrl + CapsLock` | Convert selected text (or last word) to another layout and switch |

CapsLock is permanently disabled (`SetCapsLockState "AlwaysOff"`).

## Text Conversion (Ctrl + CapsLock)

Works in two modes:

1. **Selection mode** — if you have text selected, it converts the entire selection
2. **Word mode** — if nothing is selected, it automatically selects and converts the last word on the current line

The script detects which layout the text was typed in using a character-frequency scoring algorithm, then converts to the most likely intended layout. A tooltip shows the before/after result.

This is useful when you accidentally type in the wrong layout — just press `Ctrl + CapsLock` to fix it.

## How It Works

### Architecture

The script is organized into three classes:

| Class | Responsibility |
|-------|----------------|
| `Config` | Timing constants, layout database, virtual key codes, and admin elevation flag |
| `LayoutManager` | Layout detection, system hotkey detection, switching, character mapping, text conversion, and tooltip display |
| `ClipboardHelper` | Clipboard save/restore and copy/paste operations |

### Layout Detection

On startup, the script calls `GetKeyboardLayoutList` to detect all installed layouts. It recognizes 17 languages out of the box:

English (US), Russian, German, French, Italian, Spanish, Polish, Czech, Chinese (Simplified/Traditional), Japanese, Korean, Hungarian, Turkish, Greek, Hebrew, Arabic

Unknown layouts are auto-detected and assigned generated names (e.g. `LANG_0422`). If system detection fails entirely, the script falls back to English (US) + Russian.

### Layout Switching

The script reads the registry (`HKCU\Keyboard Layout\Toggle`) to detect which system hotkey is configured, then always simulates that hotkey:

| Detected setting | Simulated keys |
|------------------|----------------|
| Alt+Shift (registry value `1`) | `Alt` + `Shift` |
| Ctrl+Shift (registry value `2`) | `Ctrl` + `Shift` |
| None / not found | `Win` + `Space` (always available on Windows 10/11) |

This single approach works universally across all window types — regular Win32 apps, Electron apps (VS Code, Discord, Slack), UWP apps, shell windows (taskbar, desktop), and everything else — because Windows itself handles the hotkey at the system level.

After switching, the script retries layout detection up to 3 times (with 50ms delays) to confirm the switch took effect.

### Character Mapping

The script dynamically generates character mappings between all installed layout pairs using `ToUnicodeEx` and `MapVirtualKeyEx` Windows APIs:

- Maps all letters (A-Z), digits (0-9), and 11 special character keys
- Generates both normal and shifted variants
- No hardcoded character tables — works with any layout combination
- Builds a reverse lookup map (character → possible source layouts) for fast text detection

### Text Layout Detection

When converting text, the script scores each installed layout by counting how many characters in the text belong to that layout's character set. The layout with the highest score is treated as the source layout.

### Clipboard Handling

Text conversion uses the clipboard internally. The script saves and restores the original clipboard contents so your clipboard is not affected.

## Configuration

All tunables are in the `Config` class at the top of `main.ahk`:

| Setting | Default | Description |
|---------|---------|-------------|
| `RequestAdmin` | `false` | Auto-request admin elevation on startup |
| `ClipboardWait` | `0.5` | ClipWait timeout (seconds) |
| `ClipboardSleep` | `150` | Sleep after clipboard operations (ms) |
| `PasteSleep` | `100` | Sleep after paste (ms) |
| `LayoutSwitchRetryDelay` | `50` | Delay between layout detection retries (ms) |
| `LayoutSwitchMaxRetries` | `3` | Max retries for layout detection |
| `TooltipShort` | `1500` | Short tooltip duration (ms) |
| `TooltipMedium` | `3000` | Medium tooltip duration (ms) |
| `TooltipLong` | `4000` | Long tooltip duration (ms) |
| `MaxDisplayLength` | `20` | Max characters shown in tooltip |

## Known Limitations

These cases cannot be solved by any AutoHotkey script:

- **Exclusive fullscreen games** — DirectInput bypasses the normal Windows input pipeline entirely
- **Remote Desktop / VM windows** — keystrokes are forwarded to the remote OS
- **Apps blocking clipboard** — text conversion won't work in apps that restrict clipboard access (password managers, some banking apps)

## Troubleshooting

**Layout doesn't switch:**
- Restart the script if layouts were added or removed
- If not running as admin, elevated apps (Task Manager, etc.) won't respond — see [Running as administrator](#running-as-administrator)

**Text conversion produces wrong results:**
- The detection algorithm needs enough characters to identify the source layout
- Single characters may not convert correctly if they exist in multiple layouts

**Text conversion doesn't work at all:**
- Both layouts must have mappable characters for the keys you typed
- Works best with Latin/Cyrillic layout pairs
- Check that clipboard access isn't blocked by the target application

**Tooltip says "No conversion available":**
- The text may already be in the correct layout
- The character mapping between your two layouts may not cover the characters used
