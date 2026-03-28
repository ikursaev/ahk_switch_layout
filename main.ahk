#Requires AutoHotkey v2.0

; ============================================================================
; CONFIGURATION
; ============================================================================

class Config {
    ; Timing constants (milliseconds)
    static ClipboardWait := 0.5          ; ClipWait timeout in seconds
    static ClipboardSleep := 150         ; Sleep after clipboard operations
    static PasteSleep := 100             ; Sleep after paste
    static LayoutSwitchRetryDelay := 50  ; Delay between layout detection retries
    static LayoutSwitchMaxRetries := 3   ; Max retries for layout detection

    ; Tooltip durations (milliseconds, negative for one-shot timer)
    static TooltipShort := 1500
    static TooltipMedium := 3000
    static TooltipLong := 4000

    ; Display settings
    static MaxDisplayLength := 20        ; Max chars to show in tooltip

    ; Auto-request admin elevation on startup (enables switching in elevated apps)
    static RequestAdmin := true

    ; Terminal window classes → copy/paste shortcuts
    ; Ctrl+C sends SIGINT in terminals, so they use different shortcuts
    static TerminalClasses := Map(
        "CASCADIA_HOSTING_WINDOW_CLASS", {copy: "^+c", paste: "^+v"},  ; Windows Terminal
        "VirtualConsoleClass",           {copy: "^+c", paste: "^+v"},  ; ConEmu / Cmder
        "mintty",                        {copy: "^{Insert}", paste: "+{Insert}"},  ; Git Bash / MSYS2
        "tmux",                          {copy: "^+c", paste: "^+v"},  ; tmux terminal
        "Alacritty",                     {copy: "^+c", paste: "^+v"}   ; Alacritty
    )

    ; Layout information database
    static LayoutInfo := Map(
        0x0409, {code: "EN-US", name: "English (US)"},
        0x0419, {code: "RU", name: "Russian"},
        0x0407, {code: "DE", name: "German"},
        0x040C, {code: "FR", name: "French"},
        0x0410, {code: "IT", name: "Italian"},
        0x0C0A, {code: "ES", name: "Spanish"},
        0x0415, {code: "PL", name: "Polish"},
        0x0405, {code: "CS", name: "Czech"},
        0x0804, {code: "ZH-CN", name: "Chinese (Simplified)"},
        0x0404, {code: "ZH-TW", name: "Chinese (Traditional)"},
        0x0411, {code: "JA", name: "Japanese"},
        0x0412, {code: "KO", name: "Korean"},
        0x040E, {code: "HU", name: "Hungarian"},
        0x041F, {code: "TR", name: "Turkish"},
        0x0408, {code: "EL", name: "Greek"},
        0x040D, {code: "HE", name: "Hebrew"},
        0x0401, {code: "AR", name: "Arabic"}
    )

    ; Virtual key codes for character mapping
    static VirtualKeys := [
        ; Letters A-Z
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
        0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54,
        0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
        ; Numbers 0-9
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        ; Special characters (;=,-./`[\]')
        0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE
    ]
}

; ============================================================================
; LAYOUT MANAGER CLASS
; ============================================================================

class LayoutManager {
    ; Instance properties
    Layouts := []
    Mappings := Map()
    CharToLayoutMap := Map()  ; Reverse lookup: char -> layout code
    CurrentLayout := ""
    SystemHotkey := ""        ; Detected system layout switch hotkey

    __New() {
        this.Initialize()
    }

    ; Initialize/refresh layout detection
    Initialize() {
        this.Layouts := []
        this.Mappings := Map()
        this.CharToLayoutMap := Map()
        this.SystemHotkey := this._DetectSystemHotkey()

        if (!this._DetectSystemLayouts()) {
            this._AddFallbackLayouts()
        }

        this.CurrentLayout := this.GetCurrentLayoutCode()
        this._CreateMappings()
        this._BuildReverseCharMap()

        this._ShowInitMessage()
    }

    ; Detect keyboard layouts from Windows
    _DetectSystemLayouts() {
        layoutCount := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")

        if (layoutCount <= 0) {
            return false
        }

        layoutBuffer := Buffer(layoutCount * A_PtrSize)
        actualCount := DllCall("GetKeyboardLayoutList", "Int", layoutCount, "Ptr", layoutBuffer.Ptr, "Int")

        if (actualCount <= 0) {
            return false
        }

        Loop actualCount {
            offset := (A_Index - 1) * A_PtrSize
            hkl := NumGet(layoutBuffer, offset, "Ptr")
            layoutId := hkl & 0xFFFF

            info := this._GetLayoutInfo(layoutId)
            this.Layouts.Push({
                id: layoutId,
                code: info.code,
                name: info.name,
                hkl: hkl
            })
        }

        return this.Layouts.Length > 0
    }

    ; Add fallback layouts if detection fails
    _AddFallbackLayouts() {
        this.Layouts.Push({id: 0x0409, code: "EN-US", name: "English (US)", hkl: 0x04090409})
        this.Layouts.Push({id: 0x0419, code: "RU", name: "Russian", hkl: 0x04190419})
    }

    ; Get layout info from config
    _GetLayoutInfo(layoutId) {
        if (Config.LayoutInfo.Has(layoutId)) {
            return Config.LayoutInfo[layoutId]
        }
        return {code: Format("LANG_{:04X}", layoutId), name: Format("Language {}", layoutId)}
    }

    ; Create character mappings between all layout pairs
    _CreateMappings() {
        for i, layout1 in this.Layouts {
            for j, layout2 in this.Layouts {
                if (i != j) {
                    key := layout1.code . "_" . layout2.code
                    this.Mappings[key] := this._GenerateMapping(layout1, layout2)
                }
            }
        }
    }

    ; Generate mapping between two layouts
    _GenerateMapping(fromLayout, toLayout) {
        mapping := Map()

        for vk in Config.VirtualKeys {
            ; Normal characters
            fromChar := this._VKToChar(vk, false, fromLayout.hkl)
            toChar := this._VKToChar(vk, false, toLayout.hkl)

            if (fromChar != "" && toChar != "" && fromChar != toChar) {
                mapping[fromChar] := toChar
            }

            ; Shifted characters
            fromCharShift := this._VKToChar(vk, true, fromLayout.hkl)
            toCharShift := this._VKToChar(vk, true, toLayout.hkl)

            if (fromCharShift != "" && toCharShift != "" && fromCharShift != toCharShift) {
                mapping[fromCharShift] := toCharShift
            }
        }

        return mapping
    }

    ; Convert virtual key to character using specific layout
    _VKToChar(vk, shift, hkl) {
        keyState := Buffer(256, 0)

        if (shift) {
            NumPut("UChar", 0x80, keyState, 0x10)  ; VK_SHIFT
        }

        scanCode := DllCall("MapVirtualKeyEx", "UInt", vk, "UInt", 0, "Ptr", hkl, "UInt")
        result := Buffer(4, 0)

        charCount := DllCall("ToUnicodeEx",
            "UInt", vk,
            "UInt", scanCode,
            "Ptr", keyState.Ptr,
            "Ptr", result.Ptr,
            "Int", 2,
            "UInt", 0,
            "Ptr", hkl,
            "Int")

        if (charCount > 0) {
            return Chr(NumGet(result, 0, "UShort"))
        }

        return ""
    }

    ; Build reverse character-to-layout map for fast detection
    _BuildReverseCharMap() {
        for layout in this.Layouts {
            for otherLayout in this.Layouts {
                if (layout.code != otherLayout.code) {
                    key := layout.code . "_" . otherLayout.code
                    if (this.Mappings.Has(key)) {
                        for char, _ in this.Mappings[key] {
                            if (!this.CharToLayoutMap.Has(char)) {
                                this.CharToLayoutMap[char] := []
                            }
                            ; Add layout code if not already present
                            found := false
                            for existingCode in this.CharToLayoutMap[char] {
                                if (existingCode == layout.code) {
                                    found := true
                                    break
                                }
                            }
                            if (!found) {
                                this.CharToLayoutMap[char].Push(layout.code)
                            }
                        }
                    }
                }
            }
        }
    }

    ; Show initialization message
    _ShowInitMessage() {
        layoutList := ""
        for layout in this.Layouts {
            layoutList .= layout.name . " (" . layout.code . "), "
        }
        layoutList := RTrim(layoutList, ", ")

        msg := "Layouts: " . layoutList
        msg .= "`nSwitch hotkey: " . this.SystemHotkey
        if (!A_IsAdmin) {
            msg .= "`n⚠ Not admin — elevated apps won't respond"
        }

        this.ShowTooltip(msg, Config.TooltipLong)
    }

    ; Get current keyboard layout code for foreground window
    GetCurrentLayoutCode() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if (!hwnd) {
            return this.Layouts.Length > 0 ? this.Layouts[1].code : "UNKNOWN"
        }

        threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        hkl := DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
        layoutId := hkl & 0xFFFF

        for layout in this.Layouts {
            if (layout.id == layoutId) {
                return layout.code
            }
        }

        return "UNKNOWN"
    }

    ; Get current layout code with retry logic
    GetCurrentLayoutCodeWithRetry() {
        Loop Config.LayoutSwitchMaxRetries {
            Sleep Config.LayoutSwitchRetryDelay
            code := this.GetCurrentLayoutCode()
            if (code != "UNKNOWN") {
                return code
            }
            Sleep Config.LayoutSwitchRetryDelay
        }
        return this.GetCurrentLayoutCode()
    }

    ; Switch to next keyboard layout using the system hotkey
    SwitchLayout() {
        this._SendSystemHotkey()
    }

    ; Detect which system hotkey is configured for layout switching
    _DetectSystemHotkey() {
        try {
            ; HKCU\Keyboard Layout\Toggle — "Language Hotkey":
            ; 1 = Alt+Shift, 2 = Ctrl+Shift, 3 = Not assigned
            hotkey := RegRead("HKCU\Keyboard Layout\Toggle", "Language Hotkey")
        } catch {
            hotkey := "3"
        }

        switch hotkey {
            case "1": return "AltShift"
            case "2": return "CtrlShift"
            default:  return "WinSpace"  ; Always available on Windows 10/11
        }
    }

    ; Simulate the detected system hotkey
    _SendSystemHotkey() {
        switch this.SystemHotkey {
            case "AltShift":
                Send "{Alt Down}{Shift Down}{Shift Up}{Alt Up}"
            case "CtrlShift":
                Send "{Ctrl Down}{Shift Down}{Shift Up}{Ctrl Up}"
            default:
                Send "{LWin Down}{Space}{LWin Up}"
        }
    }

    ; Convert text with layout awareness
    ConvertText(text, currentLayout := "") {
        if (currentLayout == "") {
            currentLayout := this.GetCurrentLayoutCode()
        }

        ; Try to detect which layout the text was typed in
        detectedLayout := this._DetectTextLayout(text)
        if (detectedLayout != "") {
            currentLayout := detectedLayout
        }

        ; Find best conversion
        for layout in this.Layouts {
            if (layout.code != currentLayout) {
                key := currentLayout . "_" . layout.code
                if (this.Mappings.Has(key)) {
                    converted := this._ApplyMapping(text, this.Mappings[key])
                    if (converted != text && converted != "") {
                        return {
                            text: converted,
                            fromLayout: currentLayout,
                            toLayout: layout.code
                        }
                    }
                }
            }
        }

        return {text: "", fromLayout: currentLayout, toLayout: ""}
    }

    ; Detect which layout text was likely typed in (optimized with reverse map)
    _DetectTextLayout(text) {
        scores := Map()

        for layout in this.Layouts {
            scores[layout.code] := 0
        }

        Loop Parse, text {
            char := A_LoopField
            if (this.CharToLayoutMap.Has(char)) {
                for layoutCode in this.CharToLayoutMap[char] {
                    if (scores.Has(layoutCode)) {
                        scores[layoutCode]++
                    }
                }
            }
        }

        bestLayout := ""
        highestScore := 0
        for code, score in scores {
            if (score > highestScore) {
                highestScore := score
                bestLayout := code
            }
        }

        return bestLayout
    }

    ; Apply character mapping to text
    _ApplyMapping(text, mapping) {
        result := ""
        Loop Parse, text {
            char := A_LoopField
            result .= mapping.Has(char) ? mapping[char] : char
        }
        return result
    }

    ; Check if foreground window is a terminal
    IsTerminal() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if (!hwnd) {
            return false
        }
        className := Buffer(256)
        DllCall("GetClassName", "Ptr", hwnd, "Ptr", className, "Int", 256)
        return Config.TerminalClasses.Has(StrGet(className))
    }

    ; Select last word in current line (skipped in terminals)
    SelectLastWord() {
        if (this.IsTerminal()) {
            return false
        }
        Send "{End}"
        Send "^+{Left}"
        return true
    }

    ; Unified tooltip display
    ShowTooltip(msg, duration := 0) {
        if (duration == 0) {
            duration := Config.TooltipMedium
        }
        ToolTip(msg)
        SetTimer(() => ToolTip(), -duration)
    }

    ; Truncate text for display
    TruncateForDisplay(text) {
        if (StrLen(text) > Config.MaxDisplayLength) {
            return SubStr(text, 1, Config.MaxDisplayLength - 3) . "..."
        }
        return text
    }
}

; ============================================================================
; CLIPBOARD HELPER
; ============================================================================

class ClipboardHelper {
    savedClipboard := ""
    copyKey := "^c"
    pasteKey := "^v"

    __New() {
        this._DetectTerminal()
    }

    ; Detect if foreground window is a terminal and set appropriate shortcuts
    _DetectTerminal() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if (!hwnd) {
            return
        }

        className := Buffer(256)
        DllCall("GetClassName", "Ptr", hwnd, "Ptr", className, "Int", 256)
        classStr := StrGet(className)

        if (Config.TerminalClasses.Has(classStr)) {
            shortcuts := Config.TerminalClasses[classStr]
            this.copyKey := shortcuts.copy
            this.pasteKey := shortcuts.paste
        }
    }

    ; Save current clipboard
    Save() {
        this.savedClipboard := ClipboardAll()
        A_Clipboard := ""
    }

    ; Restore clipboard
    Restore() {
        A_Clipboard := this.savedClipboard
        this.savedClipboard := ""
    }

    ; Copy with wait (uses terminal-aware shortcut)
    Copy() {
        Send this.copyKey
        Sleep Config.ClipboardSleep
        return ClipWait(Config.ClipboardWait) && A_Clipboard != ""
    }

    ; Paste text (uses terminal-aware shortcut)
    Paste(text) {
        A_Clipboard := text
        Send this.pasteKey
        Sleep Config.PasteSleep
    }

    ; Get current text (trimmed)
    GetText() {
        return Trim(A_Clipboard)
    }
}

; ============================================================================
; INITIALIZATION
; ============================================================================

SetCapsLockState "AlwaysOff"

; Auto-elevate to admin if configured
if (Config.RequestAdmin && !A_IsAdmin) {
    try {
        Run '*RunAs "' . A_ScriptFullPath . '"'
        ExitApp
    }
}

; Create global instance
global LM := LayoutManager()

; ============================================================================
; HOTKEY DEFINITIONS
; ============================================================================

; CapsLock: Switch layout
CapsLock:: {
    global LM
    LM.SwitchLayout()
    LM.CurrentLayout := LM.GetCurrentLayoutCodeWithRetry()
    LM.ShowTooltip("Layout: " . LM.CurrentLayout, Config.TooltipShort)
}

; Ctrl+CapsLock: Convert text
^CapsLock:: {
    global LM
    ConvertTextAction()
}

; ============================================================================
; TEXT CONVERSION ACTION
; ============================================================================

ConvertTextAction() {
    global LM

    clip := ClipboardHelper()
    clip.Save()

    ; Try to copy selected text
    if (clip.Copy()) {
        selectedText := clip.GetText()

        if (selectedText != "") {
            result := LM.ConvertText(selectedText)

            if (result.text != "" && result.text != selectedText) {
                clip.Paste(result.text)
                clip.Restore()

                displayFrom := LM.TruncateForDisplay(selectedText)
                displayTo := LM.TruncateForDisplay(result.text)
                LM.ShowTooltip("'" . displayFrom . "' → '" . displayTo . "'")

                LM.SwitchLayout()
                LM.CurrentLayout := LM.GetCurrentLayoutCodeWithRetry()
                return
            }
        }
    }

    ; No selection - try to select and convert last word (not in terminals)
    clip.Restore()
    clip.Save()

    if (!LM.SelectLastWord()) {
        clip.Restore()
        LM.ShowTooltip("Select text first (terminal detected)")
        return
    }

    if (clip.Copy()) {
        wordText := clip.GetText()

        if (wordText != "") {
            result := LM.ConvertText(wordText)

            if (result.text != "" && result.text != wordText) {
                clip.Paste(result.text)
                clip.Restore()

                LM.ShowTooltip("'" . wordText . "' → '" . result.text . "'")
                LM.SwitchLayout()
                LM.CurrentLayout := LM.GetCurrentLayoutCodeWithRetry()
                return
            }
        }

        ; No conversion available - deselect
        Send "{Right}"
    }

    clip.Restore()
    LM.ShowTooltip("No conversion available")
}
