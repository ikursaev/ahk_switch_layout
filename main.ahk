#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; CONFIGURATION
; ============================================================================

class Config {
    ; Auto-request admin elevation on startup (enables switching and fixing text in elevated apps)
    static RequestAdmin := true

    ; Timing constants (milliseconds unless noted)
    static ClipboardWait := 0.3          ; ClipWait timeout when copying a selection (seconds)
    static ClipboardRestoreDelay := 400  ; Delay before restoring the clipboard, so slow apps finish pasting first
    static LayoutSwitchRetryDelay := 30  ; Delay between checks that a layout switch took effect
    static LayoutSwitchMaxRetries := 5   ; Max checks per switch

    ; Tooltip durations (milliseconds)
    static TooltipShort := 1500
    static TooltipMedium := 3000
    static TooltipLong := 4000

    static MaxDisplayLength := 20        ; Max chars of text to show in a tooltip
    static MaxTypedKeys := 200           ; Max typed keys remembered for fixing (oldest are dropped)

    ; Terminal window classes → copy/paste shortcuts
    ; Ctrl+C sends an interrupt in terminals, so they use different shortcuts
    static TerminalClasses := Map(
        "CASCADIA_HOSTING_WINDOW_CLASS", {copy: "^+c", paste: "^+v"},              ; Windows Terminal
        "ConsoleWindowClass",            {copy: "^{Insert}", paste: "+{Insert}"},  ; Classic console (cmd, PowerShell)
        "VirtualConsoleClass",           {copy: "^+c", paste: "^+v"},              ; ConEmu / Cmder
        "mintty",                        {copy: "^{Insert}", paste: "+{Insert}"},  ; Git Bash / MSYS2
        "Alacritty",                     {copy: "^+c", paste: "^+v"},              ; Alacritty
        "org.wezfurlong.wezterm",        {copy: "^+c", paste: "^+v"}               ; WezTerm
    )

    ; Physical keys (scan codes) that type characters. Mapping by position rather than by virtual key
    ; keeps QWERTZ/AZERTY/Dvorak right, where a virtual key can sit on a different physical key.
    static ScanCodes := [
        0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,  ; ` 1-0 - =
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x2B,  ; Q-P [ ] \
        0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,              ; A-L ; '
        0x56, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35,              ; ISO extra key, Z-M , . /
        0x39                                                                            ; Space
    ]
}

; ============================================================================
; KEYBOARD LAYOUTS
; ============================================================================

; Installed layouts with a character table per physical key, plus layout switching.
; Layouts are told apart by full HKL, so two layouts of one language (e.g. US and Dvorak) stay distinct.
class Layouts {
    static List := []           ; {hkl, langId, code, name, chars, dead, keyOf}, in the system's switching order
    static ByHkl := Map()
    static SystemHotkey := ""   ; "Alt+Shift", "Ctrl+Shift" or "Win+Space"
    static _missing := Map()    ; HKLs still unknown after re-detecting, so we don't re-detect on every key
    static _charKeys := Map()

    static Init() {
        ; Build everything first and swap it in at the end, so nothing ever sees half-built tables
        charKeys := Map()
        for sc in Config.ScanCodes
            charKeys[sc] := true
        list := []
        byHkl := Map()
        for hkl in this._InstalledHkls() {
            layout := this._Build(hkl)
            list.Push(layout)
            byHkl[hkl] := layout
        }
        this._AssignCodes(list)
        this.SystemHotkey := this._DetectSystemHotkey(list)
        this._charKeys := charKeys
        this.List := list
        this.ByHkl := byHkl
        TypedKeys.Reset()  ; Recorded keys may refer to layouts that are gone
    }

    ; Re-detect layouts if any were added or removed since the last detection
    static RefreshIfChanged() {
        hkls := this._InstalledHkls()
        changed := hkls.Length != this.List.Length
        for hkl in hkls
            changed := changed || !this.ByHkl.Has(hkl)
        if (changed)
            this.Init()
    }

    ; Layout for an HKL; re-detects once if it's new (a layout added since startup)
    static Get(hkl) {
        if (hkl && !this.ByHkl.Has(hkl) && !this._missing.Has(hkl)) {
            this.Init()
            if (!this.ByHkl.Has(hkl))
                this._missing[hkl] := true
        }
        return this.ByHkl.Get(hkl, "")
    }

    static Current() => this.Get(this.CurrentHkl())
    static CurrentHkl() => this.HklOf(WinExist("A"))
    static IsCharKey(sc) => this._charKeys.Has(sc)

    ; Layout of the thread that receives a window's input
    static HklOf(hwnd) {
        if (!hwnd)
            return 0
        try {
            ; UWP apps: the frame window belongs to ApplicationFrameHost; the app's own CoreWindow gets the input
            if (WinGetClass(hwnd) == "ApplicationFrameWindow")
                hwnd := DllCall("FindWindowEx", "Ptr", hwnd, "Ptr", 0, "Str", "Windows.UI.Core.CoreWindow", "Ptr", 0, "Ptr") || hwnd
        }
        threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        return DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
    }

    ; Press the system's layout-switch hotkey and wait until the focused window reports a new layout
    static SwitchNext() {
        before := this.CurrentHkl()
        this._SendSystemHotkey()
        Loop Config.LayoutSwitchMaxRetries {
            Sleep Config.LayoutSwitchRetryDelay
            if (this.CurrentHkl() != before)
                break
        }
        return this.Current()
    }

    ; Press the switch hotkey until `target` is active (never more than once around the list)
    static SwitchTo(target) {
        Loop this.List.Length - 1 {
            if (this.CurrentHkl() == target.hkl)
                return
            this.SwitchNext()
        }
    }

    ; Character table for every physical key, normal and shifted
    static _Build(hkl) {
        langId := hkl & 0xFFFF
        layout := {hkl: hkl, langId: langId, code: "", chars: Map(), dead: Map(), keyOf: Map()}
        layout.name := this._LocaleInfo(langId, 0x72) || Format("Language {:04X}", langId)  ; LOCALE_SENGLISHDISPLAYNAME
        keyState := Buffer(256, 0)
        out := Buffer(16, 0)
        for shift in [0, 1] {  ; All unshifted keys first, so keyOf prefers them
            NumPut("UChar", shift ? 0x80 : 0, keyState, 0x10)  ; VK_SHIFT
            for sc in Config.ScanCodes {
                vk := DllCall("MapVirtualKeyEx", "UInt", sc, "UInt", 1, "Ptr", hkl, "UInt")  ; MAPVK_VSC_TO_VK
                if (!vk)
                    continue
                NumPut("UShort", 0, out)
                ; Flag 4: leave the keyboard state alone, so a dead key doesn't affect the next lookup
                n := DllCall("ToUnicodeEx", "UInt", vk, "UInt", sc, "Ptr", keyState, "Ptr", out, "Int", 8, "UInt", 4, "Ptr", hkl, "Int")
                char := n ? StrGet(out, Abs(n)) : ""  ; A dead key (-1) yields its spacing form, e.g. ^
                if (char == "")
                    continue
                key := sc * 2 + shift
                layout.chars[key] := char
                if (n < 0)
                    layout.dead[key] := true
                else if (n == 1 && !layout.keyOf.Has(char))
                    layout.keyOf[char] := key
            }
        }
        return layout
    }

    ; Short codes like "EN"; "EN-US"/"EN-GB" when two layouts share a language, plus a number if still equal
    static _AssignCodes(list) {
        counts := Map()
        for layout in list {
            layout.code := StrUpper(this._LocaleInfo(layout.langId, 0x59) || Format("{:04X}", layout.langId))  ; LOCALE_SISO639LANGNAME
            counts[layout.code] := counts.Get(layout.code, 0) + 1
        }
        seen := Map()
        for layout in list {
            if (counts[layout.code] > 1)
                layout.code := StrUpper(this._LocaleInfo(layout.langId, 0x5C) || layout.code)  ; LOCALE_SNAME
            seen[layout.code] := seen.Get(layout.code, 0) + 1
            if (seen[layout.code] > 1)
                layout.code .= " " seen[layout.code]
        }
    }

    static _LocaleInfo(langId, type) {
        buf := Buffer(256, 0)
        return DllCall("GetLocaleInfoW", "UInt", langId, "UInt", type, "Ptr", buf, "Int", 128) ? StrGet(buf) : ""
    }

    static _InstalledHkls() {
        count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")
        buf := Buffer(Max(count, 1) * A_PtrSize)
        count := DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", buf, "Int")
        hkls := []
        Loop count
            hkls.Push(NumGet(buf, (A_Index - 1) * A_PtrSize, "Ptr"))
        return hkls
    }

    ; HKCU\Keyboard Layout\Toggle "Language Hotkey": 1 = Alt+Shift, 2 = Ctrl+Shift, 3 = not assigned
    static _DetectSystemHotkey(list) {
        ; That hotkey only cycles languages; Win+Space also reaches the other layouts of one language
        langs := Map()
        for layout in list {
            if (langs.Has(layout.langId))
                return "Win+Space"
            langs[layout.langId] := true
        }
        try {
            switch RegRead("HKCU\Keyboard Layout\Toggle", "Language Hotkey") {
                case "1": return "Alt+Shift"
                case "2": return "Ctrl+Shift"
            }
        }
        return "Win+Space"  ; Always available on Windows 10/11
    }

    static _SendSystemHotkey() {
        switch this.SystemHotkey {
            case "Alt+Shift":
                Send "{Alt Down}{Shift Down}{Shift Up}{Alt Up}"
            case "Ctrl+Shift":
                Send "{Ctrl Down}{Shift Down}{Shift Up}{Ctrl Up}"
            default:
                Send "{LWin Down}{Space}{LWin Up}"
        }
    }
}

; ============================================================================
; TYPED KEYS
; ============================================================================

; Remembers the physical keys typed since the caret last moved, so text can be fixed by deleting it and
; retyping the same keys in another layout: no clipboard involved, and it works in terminals too.
class TypedKeys {
    static Keys := []                ; {key: scanCode * 2 + shift, hkl: layout it was typed in}
    static Hwnd := 0                 ; Window the keys were typed into
    static SelectionLikely := false  ; Text was probably just selected with the mouse or keyboard
    static _hook := ""
    static _mods := Map()            ; Held modifier VK → tick of its last key-down, tracked in event order (GetKeyState can run ahead of the queue)
    static _afterDeadKey := false
    static _downAt := {x: 0, y: 0}
    static _lastClick := {x: 0, y: 0, tick: 0}
    static _overText := false
    static _clickSelects := false

    static Start() {
        this._hook := InputHook("V I1 L0")  ; Watch only: keys pass through, and our own Send is ignored
        this._hook.KeyOpt("{All}", "N")
        this._hook.OnKeyDown := ObjBindMethod(this, "_KeyDown")
        this._hook.OnKeyUp := ObjBindMethod(this, "_KeyUp")
        this._hook.Start()
    }

    static Reset() {
        this.Keys := []
        this.Hwnd := 0
        this._afterDeadKey := false
    }

    ; Keys to fix: the last word plus any spaces after it, or (wholePhrase) everything typed
    static Span(wholePhrase) {
        if (this.Hwnd != WinExist("A")) {  ; Focus moved to another window
            this.Reset()
            return []
        }
        keys := this.Keys
        last := keys.Length
        while (last && this._IsSpace(keys[last]))
            last--
        if (!last)
            return []
        first := last
        while (first > 1 && (wholePhrase || !this._IsSpace(keys[first - 1])))
            first--
        while (this._IsSpace(keys[first]))  ; Leading spaces need no fixing
            first++
        span := []
        Loop keys.Length - first + 1
            span.Push(keys[first + A_Index - 1])
        return span
    }

    ; A click moves the caret; dragging, double/triple-clicking or Shift+clicking over text selects it
    static MouseDown() {
        MouseGetPos(&x, &y)
        this.Reset()
        this._overText := A_Cursor == "IBeam" || A_Cursor == "Unknown"  ; Not a title bar, scroll bar or border
        multiClick := A_TickCount - this._lastClick.tick <= DllCall("GetDoubleClickTime", "UInt") && this._Near(this._lastClick, x, y)
        this._clickSelects := multiClick || GetKeyState("Shift")
        this._downAt := {x: x, y: y}
    }

    static MouseUp() {
        MouseGetPos(&x, &y)
        this.SelectionLikely := this._overText && (this._clickSelects || !this._Near(this._downAt, x, y))
        this._lastClick := {x: x, y: y, tick: A_TickCount}
    }

    static _KeyDown(ih, vk, sc) {
        Critical  ; Layouts.Get may rebuild the layout tables, which a hotkey mustn't interrupt
        if (this._IsModifier(vk)) {
            this._mods[vk] := A_TickCount
            return
        }
        if (this._IsIgnored(vk))
            return
        this._ForgetStaleMods()
        shift := this._Held(0x10, 0xA0, 0xA1)
        ctrl := this._Held(0x11, 0xA2, 0xA3)
        altOrWin := this._Held(0x12, 0xA4, 0xA5, 0x5B, 0x5C)

        if (ctrl || altOrWin) {
            ; Shortcuts (and AltGr) may change the text in ways we can't follow; in terminals even Ctrl+C discards the line
            this.Reset()
            isCopy := ctrl && !altOrWin && (vk == 0x43 || vk == 0x2D)  ; Ctrl+C / Ctrl+Insert keep the selection
            if (!isCopy)
                this.SelectionLikely := ctrl && !altOrWin && (vk == 0x41 || shift && this._IsNavigation(vk))  ; Ctrl+A, Ctrl+Shift+arrows
            return
        }
        if (this._IsNavigation(vk)) {
            this.Reset()
            this.SelectionLikely := shift  ; Shift+arrows/Home/End select text
            return
        }
        this.SelectionLikely := false
        if (vk == 0x08) {  ; Backspace
            if (this.Keys.Length && !this._afterDeadKey && WinExist("A") == this.Hwnd)
                this.Keys.Pop()
            else
                this.Reset()
        } else if (vk != 0xE7 && Layouts.IsCharKey(sc)) {  ; vkE7: a character another program injected; sc holds its code
            this._Record(sc, shift)
        } else {
            this.Reset()  ; Enter, Tab, Esc, Delete, numpad, function keys…
        }
    }

    static _KeyUp(ih, vk, sc) {
        if (this._mods.Has(vk))
            this._mods.Delete(vk)
    }

    static _Record(sc, shift) {
        hwnd := WinExist("A")
        layout := Layouts.Get(Layouts.HklOf(hwnd))
        key := sc * 2 + shift
        isDead := layout && layout.dead.Has(key)
        if (!layout || !layout.chars.Has(key) || isDead || this._afterDeadKey) {
            ; Can't tell what this typed: unknown layout, no character, or part of a dead-key sequence (^ + e = ê)
            this.Reset()
            this._afterDeadKey := isDead
            return
        }
        if (hwnd != this.Hwnd) {
            this.Reset()
            this.Hwnd := hwnd
        }
        this.Keys.Push({key: key, hkl: layout.hkl})
        if (this.Keys.Length > Config.MaxTypedKeys)
            this.Keys.RemoveAt(1)
    }

    ; A modifier's key-up is lost when it goes to an elevated window or the secure desktop (Win+L, Ctrl+Alt+Del,
    ; UAC prompts). Drop modifiers that are up now and haven't sent a key-down (held keys repeat) for a while;
    ; a recent one may just be up already because this callback lags behind the keyboard.
    static _ForgetStaleMods() {
        stale := []
        for vk, lastDown in this._mods
            if (A_TickCount - lastDown > 1000 && !(DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000))
                stale.Push(vk)
        for vk in stale
            this._mods.Delete(vk)
    }

    static _Held(vks*) {
        for vk in vks
            if (this._mods.Has(vk))
                return true
        return false
    }

    static _Near(point, x, y) {
        tolerance := DllCall("GetSystemMetrics", "Int", 68)  ; SM_CXDRAG: how far the mouse moves before a click becomes a drag
        return Abs(x - point.x) <= tolerance && Abs(y - point.y) <= tolerance
    }

    static _IsSpace(k) => k.key // 2 == 0x39
    static _IsModifier(vk) => (vk >= 0x10 && vk <= 0x12) || (vk >= 0xA0 && vk <= 0xA5) || vk == 0x5B || vk == 0x5C
    static _IsNavigation(vk) => vk >= 0x21 && vk <= 0x28  ; PgUp, PgDn, End, Home, arrows
    ; CapsLock (our hotkeys), Num/Scroll Lock, media keys, the vkE8 mask key, Fn: none of them touch the text
    static _IsIgnored(vk) => vk == 0x14 || vk == 0x90 || vk == 0x91 || (vk >= 0xA6 && vk <= 0xB7) || vk == 0xE8 || vk == 0xFF
}

; ============================================================================
; CONVERSION
; ============================================================================

; Converts key sequences between layouts. A sequence holds {key, hkl} objects (a physical key and the
; layout it was typed in) and, for pasted text, plain strings for characters no key of the layout types.
class Converter {
    ; Text the keys produce: each in its own layout, or in `layout` where that has a character for the key
    static Text(keys, layout := "") {
        text := ""
        for k in keys
            text .= this._Char(k, layout)
        return text
    }

    ; Layout that changes the most characters; ties go to the first one after `fromHkl` in switching order
    static PickTarget(keys, fromHkl) {
        list := Layouts.List
        start := 0
        for i, layout in list
            if (layout.hkl == fromHkl)
                start := i
        best := ""
        bestChanges := 0
        Loop list.Length {
            layout := list[Mod(start + A_Index - 1, list.Length) + 1]
            changes := 0
            for k in keys
                if (IsObject(k) && this._Char(k, layout) !== this._Char(k))
                    changes++
            if (changes > bestChanges) {
                best := layout
                bestChanges := changes
            }
        }
        return best
    }

    ; Layout the text was most likely typed in. Each character votes for the layouts that have it, split
    ; between them, so characters every layout has decide nothing; ties go to the current layout.
    static DetectLayout(text) {
        scores := Map()
        Loop Parse text {
            owners := []
            for layout in Layouts.List
                if (layout.keyOf.Has(A_LoopField))
                    owners.Push(layout.hkl)
            for hkl in owners
                scores[hkl] := scores.Get(hkl, 0) + 1 / owners.Length
        }
        current := Layouts.CurrentHkl()
        best := ""
        bestScore := 0
        for layout in Layouts.List {
            score := scores.Get(layout.hkl, 0)
            if (score > bestScore || (score > 0 && score == bestScore && layout.hkl == current)) {
                best := layout
                bestScore := score
            }
        }
        return best
    }

    ; Keys that type `text` in `layout`; characters it can't type stay as plain strings
    static FromText(text, layout) {
        keys := []
        Loop Parse text
            keys.Push(layout.keyOf.Has(A_LoopField) ? {key: layout.keyOf[A_LoopField], hkl: layout.hkl} : A_LoopField)
        return keys
    }

    static _Char(k, layout := "") {
        if (!IsObject(k))
            return k
        if (layout && layout.chars.Has(k.key))
            return layout.chars[k.key]
        return Layouts.ByHkl[k.hkl].chars[k.key]
    }
}

; ============================================================================
; CLIPBOARD
; ============================================================================

; Copies the selection and pastes the result, then puts the user's clipboard back
class Clip {
    static _saved := ""
    static _pending := false
    static _seq := 0
    static _timer := ""

    ; Copy/paste shortcuts for the active window (terminals use their own)
    static Shortcuts() {
        cls := ""
        try cls := WinGetClass("A")
        if (Config.TerminalClasses.Has(cls)) {
            keys := Config.TerminalClasses[cls]
            return {copy: keys.copy, paste: keys.paste, terminal: true}
        }
        return {copy: "^c", paste: "^v", terminal: false}
    }

    ; Copy the selection as text; "" if nothing (or only files) got copied. Follow up with Paste or Restore.
    static Copy(copyKey) {
        this._FinishPaste()  ; Restore after an earlier paste first, so we save the user's clipboard, not ours
        this._saved := ClipboardAll()
        A_Clipboard := ""
        Send copyKey
        if (!ClipWait(Config.ClipboardWait) || DllCall("IsClipboardFormatAvailable", "UInt", 15))  ; CF_HDROP: files from Explorer
            return ""
        return A_Clipboard
    }

    static Paste(text, pasteKey) {
        A_Clipboard := text
        this._seq := DllCall("GetClipboardSequenceNumber", "UInt")
        Send pasteKey
        ; Restore later: slow apps (Electron, Office) read the clipboard after the shortcut is sent
        this._pending := true
        if (!this._timer)
            this._timer := ObjBindMethod(this, "_FinishPaste")
        SetTimer(this._timer, -Config.ClipboardRestoreDelay)
    }

    static Restore() {
        A_Clipboard := this._saved
        this._saved := ""
    }

    static _FinishPaste() {
        if (!this._pending)
            return
        this._pending := false
        SetTimer(this._timer, 0)  ; We may be finishing early, before a new copy
        if (DllCall("GetClipboardSequenceNumber", "UInt") == this._seq)  ; Skip if something new was copied since
            this.Restore()
        this._saved := ""
    }
}

; ============================================================================
; FIXING TEXT
; ============================================================================

; Fix the last typed word (or wholePhrase: everything typed since the caret last moved). With nothing
; typed, fix the selection: Ctrl+CapsLock only if one was seen being made, Ctrl+Shift+CapsLock regardless.
FixText(wholePhrase) {
    Layouts.RefreshIfChanged()
    span := TypedKeys.Span(wholePhrase)
    if (span.Length)
        FixTyped(span)
    else if (wholePhrase || TypedKeys.SelectionLikely)
        FixSelection(TypedKeys.SelectionLikely)
    else
        ShowTooltip("Nothing to fix: type a word or select text first")
}

; Delete the typed text and retype the same keys in the layout that changes it the most
FixTyped(span) {
    target := Converter.PickTarget(span, span[1].hkl)  ; span[1] is never a space, which may be typed after a switch
    if (!target) {
        ShowTooltip("No conversion available")
        return
    }
    before := Converter.Text(span)
    after := Converter.Text(span, target)
    ; SendText types Unicode characters, so the result doesn't depend on the active layout
    Send "{Backspace " StrLen(before) "}"
    SendText after
    for k in span
        if (target.chars.Has(k.key))
            k.hkl := target.hkl
    Layouts.SwitchTo(target)
    ShowConversion(before, after, target)
}

; Copy the selection, paste it back converted, and switch to the layout it was converted to.
; selectionSeen: the script saw text being selected (otherwise nothing may be selected at all).
FixSelection(selectionSeen) {
    shortcuts := Clip.Shortcuts()
    text := Clip.Copy(shortcuts.copy)
    ; With nothing selected, editors like VS Code copy the whole line: don't paste a converted copy of it
    if (text == "" || (!selectionSeen && text ~= "\R$")) {
        Clip.Restore()
        ShowTooltip("Nothing selected")
        return
    }
    if (shortcuts.terminal && text ~= "[\r\n]") {
        Clip.Restore()
        ShowTooltip("Select a single line: a terminal would run every pasted line")
        return
    }
    from := Converter.DetectLayout(text)
    keys := from ? Converter.FromText(text, from) : []
    target := from ? Converter.PickTarget(keys, from.hkl) : ""
    if (!target) {
        Clip.Restore()
        ShowTooltip("No conversion available")
        return
    }
    after := Converter.Text(keys, target)
    Clip.Paste(after, shortcuts.paste)
    TypedKeys.SelectionLikely := false  ; The paste replaced it
    Layouts.SwitchTo(target)
    ShowConversion(text, after, target)
}

; ============================================================================
; TOOLTIPS
; ============================================================================

ShowTooltip(msg, duration := 0) {
    static hide := () => ToolTip()
    ToolTip(msg)
    SetTimer(hide, -(duration || Config.TooltipMedium))  ; Same timer every time, so a newer tooltip isn't hidden early
}

ShowConversion(before, after, layout) {
    ShowTooltip("'" Shorten(before) "' → '" Shorten(after) "' (" layout.code ")")
}

Shorten(text) {
    text := RegExReplace(text, "\R", "⏎")
    return StrLen(text) > Config.MaxDisplayLength ? SubStr(text, 1, Config.MaxDisplayLength - 1) "…" : text
}

ShowStartupMessage() {
    names := ""
    for layout in Layouts.List
        names .= ", " layout.name " (" layout.code ")"
    msg := "Layouts: " SubStr(names, 3)
    msg .= "`nSwitch hotkey: " Layouts.SystemHotkey
    if (!A_IsAdmin)
        msg .= "`n⚠ Not admin — elevated apps won't respond"
    ShowTooltip(msg, Config.TooltipLong)
}

; ============================================================================
; STARTUP
; ============================================================================

; Auto-elevate to admin if configured (/restart replaces this instance without a prompt)
if (Config.RequestAdmin && !A_IsAdmin) {
    try {
        if (A_IsCompiled)
            Run '*RunAs "' A_ScriptFullPath '" /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        ExitApp
    }
}

SetCapsLockState "AlwaysOff"
CoordMode "Mouse", "Screen"
Layouts.Init()
TypedKeys.Start()
ShowStartupMessage()

; ============================================================================
; HOTKEYS
; ============================================================================

; CapsLock: switch to the next layout
CapsLock:: {
    Critical
    layout := Layouts.SwitchNext()
    ShowTooltip("Layout: " (layout ? layout.code : "unknown"), Config.TooltipShort)
    Critical "Off"
    KeyWait "CapsLock"  ; One switch per press, however long it's held
}

; Ctrl+CapsLock: fix the last typed word (or the selection)
^CapsLock:: {
    Critical
    FixText(false)
    Critical "Off"
    KeyWait "CapsLock"
}

; Ctrl+Shift+CapsLock: fix everything typed since the caret last moved (or the selection)
^+CapsLock:: {
    ; Ctrl+Shift can be a Windows layout hotkey (for languages, or for layouts within one), which fires when it's
    ; released with no other key in between. Tap an unassigned key now, and wait for Shift to be let go, because
    ; every Send releases and re-presses held modifiers, and that bare re-press would read as the hotkey too.
    Send "{Blind}{vkE8}"
    KeyWait "Shift"
    Critical
    FixText(true)
    Critical "Off"
    KeyWait "CapsLock"
}

; Mouse clicks move the caret, so the typed keys no longer end at it
~LButton::TypedKeys.MouseDown()
~LButton Up::TypedKeys.MouseUp()
~RButton::
~MButton::
~XButton1::
~XButton2::TypedKeys.Reset()
