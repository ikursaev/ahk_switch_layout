# Keyboard Layout Switcher for AutoHotkey v2

An AutoHotkey script that provides seamless keyboard layout switching and text conversion between layouts.

## Requirements

- Windows 10/11
- [AutoHotkey v2.0](https://www.autohotkey.com/)
- Alt+Shift must be configured as your Windows layout switch shortcut (Settings → Time & Language → Typing → Advanced keyboard settings)

## Features

### Hotkeys

| Hotkey | Action |
|--------|--------|
| `CapsLock` | Switch to the next keyboard layout |
| `Ctrl + CapsLock` | Convert selected text (or last word) to another layout and switch |
| `Ctrl + Alt + R` | Refresh detected keyboard layouts |
| `Ctrl + Alt + I` | Show current layout info |

### Smart Text Conversion (Ctrl + CapsLock)

Works in two modes:

1. **Selection Mode**: If you have text selected, it converts the entire selection
2. **Word Mode**: If nothing is selected, it automatically selects and converts the last word on the current line

This is useful when you accidentally type in the wrong layout - just press `Ctrl + CapsLock` to fix it.

## How It Works

### Layout Detection

On startup, the script automatically detects all keyboard layouts installed on your system using the Windows `GetKeyboardLayoutList` API. It supports 17+ languages out of the box:

- English (US), Russian, German, French, Italian, Spanish, Polish, Czech
- Chinese (Simplified/Traditional), Japanese, Korean
- Hungarian, Turkish, Greek, Hebrew, Arabic

Unknown layouts are detected and assigned auto-generated names.

### Layout Switching

The script uses a hybrid approach for maximum reliability:

**For regular application windows:**
- Uses the Windows `PostMessage` API with `WM_INPUTLANGCHANGEREQUEST` message
- Directly requests the layout change from the target window
- More reliable than simulating keystrokes

**For shell windows (taskbar, desktop, system tray):**
- Detects shell window classes: `Shell_TrayWnd`, `Shell_SecondaryTrayWnd`, `Progman`, `WorkerW`, `NotifyIconOverflowWindow`
- Falls back to simulating `Alt+Shift` which Windows handles system-wide

### Character Mapping

The script dynamically generates character mappings between all installed layouts using the Windows `ToUnicodeEx` API. This means:

- No hardcoded character tables
- Works with any layout combination
- Automatically handles shifted characters

## Notes

- CapsLock is always kept off (`SetCapsLockState "AlwaysOff"`)
- A tooltip briefly shows the current layout after switching
- The clipboard is preserved when converting text

## Troubleshooting

**Layout doesn't switch:**
- Make sure Alt+Shift is set as your Windows layout switcher
- Try pressing `Ctrl + Alt + R` to refresh layouts

**Text conversion doesn't work:**
- The script needs both layouts to have mappable characters
- Works best with Latin/Cyrillic layout pairs
