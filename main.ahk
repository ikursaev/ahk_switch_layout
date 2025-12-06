#Requires AutoHotkey v2.0

SetCapsLockState "AlwaysOff"

; Global variables for layout switching
CurrentLayoutIndex := 0
AvailableLayouts := []
LayoutMappings := Map()
CharacterLayoutMap := Map() ; Track which layout each character was typed in
LastTypedWord := ""
WordBuffer := ""
IsTrackingWord := false
LastExecutionTime := 0
CurrentActiveLayout := ""

; Initialize layouts on script start
InitializeLayouts()

; Function to get all available keyboard layouts from system
InitializeLayouts() {
    global AvailableLayouts, LayoutMappings, CurrentActiveLayout

    ; Clear existing layouts
    AvailableLayouts := []

    ; Get number of keyboard layouts
    layoutCount := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0)

    if (layoutCount > 0) {
        ; Allocate buffer for layout handles
        layoutBuffer := Buffer(layoutCount * A_PtrSize)

        ; Get actual layout handles
        actualCount := DllCall("GetKeyboardLayoutList", "Int", layoutCount, "Ptr", layoutBuffer.Ptr)

        ; Process each layout
        Loop actualCount {
            offset := (A_Index - 1) * A_PtrSize
            hkl := NumGet(layoutBuffer, offset, "Ptr")
            layoutId := hkl & 0xFFFF

            ; Get layout name
            layoutName := GetLayoutName(layoutId)

            AvailableLayouts.Push({
                id: layoutId,
                name: layoutName,
                hkl: hkl,
                friendlyName: GetLayoutFriendlyName(layoutId)
            })
        }
    }

    ; If no layouts detected, add fallback
    if (AvailableLayouts.Length == 0) {
        AvailableLayouts.Push({id: 0x0409, name: "EN-US", hkl: 0x04090409, friendlyName: "English (US)"})
        AvailableLayouts.Push({id: 0x0419, name: "RU", hkl: 0x04190419, friendlyName: "Russian"})
    }

    ; Get current layout
    CurrentActiveLayout := GetCurrentLayoutName()

    ; Generate dynamic mappings between all layout pairs
    CreateDynamicLayoutMappings()

    ; Show detected layouts
    layoutList := ""
    for layout in AvailableLayouts {
        layoutList .= layout.friendlyName . " (" . layout.name . "), "
    }
    layoutList := RTrim(layoutList, ", ")

    ToolTip("Detected layouts: " . layoutList)
    SetTimer(() => ToolTip(), -4000)
}

; Get layout name from ID
GetLayoutName(layoutId) {
    layoutNames := Map(
        0x0409, "EN-US",    ; English (US)
        0x0419, "RU",       ; Russian
        0x0407, "DE",       ; German
        0x040C, "FR",       ; French
        0x0410, "IT",       ; Italian
        0x0C0A, "ES",       ; Spanish
        0x0415, "PL",       ; Polish
        0x0405, "CS",       ; Czech
        0x0804, "ZH-CN",    ; Chinese (Simplified)
        0x0404, "ZH-TW",    ; Chinese (Traditional)
        0x0411, "JA",       ; Japanese
        0x0412, "KO",       ; Korean
        0x040E, "HU",       ; Hungarian
        0x041F, "TR",       ; Turkish
        0x0408, "EL",       ; Greek
        0x040D, "HE",       ; Hebrew
        0x0401, "AR"        ; Arabic
    )

    return layoutNames.Has(layoutId) ? layoutNames[layoutId] : Format("LANG_{:04X}", layoutId)
}

; Get friendly name for layout
GetLayoutFriendlyName(layoutId) {
    friendlyNames := Map(
        0x0409, "English (US)",
        0x0419, "Russian",
        0x0407, "German",
        0x040C, "French",
        0x0410, "Italian",
        0x0C0A, "Spanish",
        0x0415, "Polish",
        0x0405, "Czech",
        0x0804, "Chinese (Simplified)",
        0x0404, "Chinese (Traditional)",
        0x0411, "Japanese",
        0x0412, "Korean",
        0x040E, "Hungarian",
        0x041F, "Turkish",
        0x0408, "Greek",
        0x040D, "Hebrew",
        0x0401, "Arabic"
    )

    return friendlyNames.Has(layoutId) ? friendlyNames[layoutId] : Format("Language {}", layoutId)
}

; Create dynamic character mappings between layouts
CreateDynamicLayoutMappings() {
    global LayoutMappings, AvailableLayouts

    ; Clear existing mappings
    LayoutMappings := Map()

    ; Generate mappings for each pair of layouts
    for i, layout1 in AvailableLayouts {
        for j, layout2 in AvailableLayouts {
            if (i != j) {
                mappingKey := layout1.name . "_" . layout2.name
                LayoutMappings[mappingKey] := GenerateLayoutMapping(layout1, layout2)
            }
        }
    }
}

; Generate character mapping between two specific layouts
GenerateLayoutMapping(fromLayout, toLayout) {
    mapping := Map()

    ; Define virtual key codes for characters we want to map
    virtualKeys := [
        ; Letters
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
        0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54,
        0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
        ; Numbers
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        ; Special characters
        0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE
    ]

    ; Generate mappings for each virtual key
    for vk in virtualKeys {
        ; Get character from source layout
        fromChar := GetCharFromVirtualKey(vk, false, fromLayout.hkl)
        fromCharShift := GetCharFromVirtualKey(vk, true, fromLayout.hkl)

        ; Get character from target layout
        toChar := GetCharFromVirtualKey(vk, false, toLayout.hkl)
        toCharShift := GetCharFromVirtualKey(vk, true, toLayout.hkl)

        ; Add to mapping if characters are different and valid
        if (fromChar != "" && toChar != "" && fromChar != toChar) {
            mapping[fromChar] := toChar
        }
        if (fromCharShift != "" && toCharShift != "" && fromCharShift != toCharShift) {
            mapping[fromCharShift] := toCharShift
        }
    }

    return mapping
}

; Get character from virtual key using specific keyboard layout
GetCharFromVirtualKey(vk, shift, hkl) {
    ; Create keyboard state array
    keyState := Buffer(256, 0)

    ; Set shift state if needed
    if (shift) {
        NumPut("UChar", 0x80, keyState, 0x10) ; VK_SHIFT
    }

    ; Convert virtual key to Unicode
    result := Buffer(4, 0)
    scanCode := DllCall("MapVirtualKeyEx", "UInt", vk, "UInt", 0, "Ptr", hkl)

    charCount := DllCall("ToUnicodeEx",
        "UInt", vk,           ; Virtual key
        "UInt", scanCode,     ; Scan code
        "Ptr", keyState.Ptr,  ; Keyboard state
        "Ptr", result.Ptr,    ; Buffer for Unicode char
        "Int", 2,             ; Buffer size
        "UInt", 0,            ; Flags
        "Ptr", hkl,           ; Keyboard layout
        "Int")

    if (charCount > 0) {
        return Chr(NumGet(result, 0, "UShort"))
    }

    return ""
}

; Get current keyboard layout name for the foreground window
GetCurrentLayoutName() {
    global AvailableLayouts

    ; Get the foreground window's thread to check its layout
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    threadId := hwnd ? DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt") : 0

    hkl := DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
    layoutId := hkl & 0xFFFF

    for layout in AvailableLayouts {
        if (layout.id == layoutId) {
            return layout.name
        }
    }
    return "UNKNOWN"
}

; Switch to next keyboard layout using Windows API
SwitchToNextLayout() {
    global AvailableLayouts, CurrentLayoutIndex

    ; Get foreground window
    hwnd := DllCall("GetForegroundWindow", "Ptr")

    ; Check if this is a shell window (taskbar, desktop, etc.) that needs Alt+Shift
    useAltShift := false
    if (hwnd) {
        ; Get window class name
        className := Buffer(256)
        DllCall("GetClassName", "Ptr", hwnd, "Ptr", className, "Int", 256)
        classStr := StrGet(className)

        ; Shell window classes that don't respond well to PostMessage
        shellClasses := ["Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW", "NotifyIconOverflowWindow"]
        for shellClass in shellClasses {
            if (classStr = shellClass) {
                useAltShift := true
                break
            }
        }
    } else {
        ; No foreground window - use Alt+Shift
        useAltShift := true
    }

    if (useAltShift) {
        ; Use system shortcut for shell windows and desktop
        Send "{Alt Down}{Shift Down}{Shift Up}{Alt Up}"
    } else {
        ; Use PostMessage API for regular application windows
        threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        currentHKL := DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
        currentId := currentHKL & 0xFFFF

        ; Find current index and calculate next
        nextIndex := 1
        for i, layout in AvailableLayouts {
            if (layout.id == currentId) {
                nextIndex := (i >= AvailableLayouts.Length) ? 1 : i + 1
                break
            }
        }

        ; Post layout change message
        targetHKL := AvailableLayouts[nextIndex].hkl
        DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0050, "Ptr", 0, "Ptr", targetHKL)
    }
}


; Convert text between layouts with layout awareness
ConvertTextWithLayoutAwareness(text, currentLayout := "") {
    global LayoutMappings, AvailableLayouts, CharacterLayoutMap

    ; If no current layout specified, try to detect it
    if (currentLayout == "") {
        currentLayout := GetCurrentLayoutName()
    }

    ; Try to determine which layout the text was actually typed in
    ; by checking which characters exist in which layout mappings
    detectedLayout := DetectTextLayout(text)
    if (detectedLayout != "") {
        currentLayout := detectedLayout
    }

    ; Find the best target layout for conversion
    bestConversion := ""
    targetLayout := ""

    ; Try converting to each available layout
    for layout in AvailableLayouts {
        if (layout.name != currentLayout) {
            mappingKey := currentLayout . "_" . layout.name
            if (LayoutMappings.Has(mappingKey)) {
                converted := ConvertTextUsingMapping(text, LayoutMappings[mappingKey])
                if (converted != text && converted != "") {
                    bestConversion := converted
                    targetLayout := layout.name
                    break
                }
            }
        }
    }

    return {text: bestConversion, fromLayout: currentLayout, toLayout: targetLayout}
}

; Detect which layout text was likely typed in
DetectTextLayout(text) {
    global LayoutMappings, AvailableLayouts

    ; Count how many characters can be mapped from each layout
    layoutScores := Map()

    for layout in AvailableLayouts {
        layoutScores[layout.name] := 0
    }

    ; Check each character against each layout's mappings
    Loop Parse, text {
        char := A_LoopField
        for layout in AvailableLayouts {
            for otherLayout in AvailableLayouts {
                if (layout.name != otherLayout.name) {
                    mappingKey := layout.name . "_" . otherLayout.name
                    if (LayoutMappings.Has(mappingKey) && LayoutMappings[mappingKey].Has(char)) {
                        layoutScores[layout.name]++
                    }
                }
            }
        }
    }

    ; Find layout with highest score
    bestLayout := ""
    highestScore := 0
    for layoutName, score in layoutScores {
        if (score > highestScore) {
            highestScore := score
            bestLayout := layoutName
        }
    }

    return bestLayout
}

; Convert text using a specific mapping
ConvertTextUsingMapping(text, mapping) {
    result := ""

    Loop Parse, text {
        char := A_LoopField
        if (mapping.Has(char)) {
            result .= mapping[char]
        } else {
            result .= char
        }
    }

    return result
}

; Select the last word in the current line
SelectLastWordInLine() {
    ; Go to start of line
    Send "{Home}"

    ; Get the entire line content
    Send "+{End}"
    A_Clipboard := ""
    Send "^c"

    if (!ClipWait(0.1)) {
        Send "{End}"
        return
    }

    originalLineText := A_Clipboard
    Send "{Home}"  ; Go back to start

    ; Find the last word in the line
    ; Remove trailing whitespace and newlines for analysis
    lineText := RTrim(originalLineText, " `t`n`r")

    if (StrLen(lineText) == 0) {
        Send "{End}"
        return
    }

    ; Find the start of the last word by searching backwards for whitespace
    lastWordStart := 1  ; Default to start of line if no whitespace found

    ; Find where the last word starts (after the last space or line break)
    Loop StrLen(lineText) {
        charPos := StrLen(lineText) - A_Index + 1
        char := SubStr(lineText, charPos, 1)

        if (char == " " || char == "`t" || char == "`n" || char == "`r") {
            lastWordStart := charPos + 1
            break
        }
    }

    ; Calculate word length (use trimmed version for accurate length)
    wordLength := StrLen(lineText) - lastWordStart + 1

    ; Move to the start of the last word
    Loop (lastWordStart - 1) {
        Send "{Right}"
    }

    ; Select the word
    Send "+{Right " . wordLength . "}"
}

; Get current layout name with retry logic
GetCurrentLayoutNameWithRetry(maxRetries := 3) {
    Loop maxRetries {
        Sleep 50  ; Give system time to process layout change
        layoutName := GetCurrentLayoutName()
        if (layoutName != "UNKNOWN") {
            return layoutName
        }
        Sleep 50
    }
    return GetCurrentLayoutName()  ; Return whatever we got on final attempt
}

; Main hotkey: Ctrl + CapsLock for smart text conversion (works with selected text or current word)
^CapsLock:: {
    ; Save current clipboard
    oldClipboard := ClipboardAll()

    ; Clear clipboard and try to copy selected text
    A_Clipboard := ""
    Send "^c"
    Sleep 300  ; Wait for copy

    ; Check if we got text (meaning there was a selection)
    if (A_Clipboard != "" && Trim(A_Clipboard) != "") {
        ; SELECTION MODE: Process the entire selection
        selectedText := Trim(A_Clipboard)

        ; Convert the text
        currentLayout := GetCurrentLayoutName()
        conversionResult := ConvertTextWithLayoutAwareness(selectedText, currentLayout)

        if (conversionResult.text != "" && conversionResult.text != selectedText) {
            ; Use clipboard method to replace text reliably
            A_Clipboard := conversionResult.text
            Send "^v"  ; Paste the converted text
            Sleep 100  ; Give paste time to complete

            ; Restore clipboard immediately after this operation
            A_Clipboard := oldClipboard

            ; Show success message
            displayText := selectedText
            displayConverted := conversionResult.text

            if (StrLen(displayText) > 20) {
                displayText := SubStr(displayText, 1, 17) . "..."
            }
            if (StrLen(displayConverted) > 20) {
                displayConverted := SubStr(displayConverted, 1, 17) . "..."
            }

            ToolTip("SELECTION: '" . displayText . "' → '" . displayConverted . "'")

            ; Switch layout and finish
            SwitchToNextLayout()
            global CurrentActiveLayout
            CurrentActiveLayout := GetCurrentLayoutName()
            SetTimer(() => ToolTip(), -3000)
            return
        } else {
            ; No conversion available for selection
            A_Clipboard := oldClipboard
            Send "{Right}"  ; Deselect
            ToolTip("No conversion for selection")
            SwitchToNextLayout()
            global CurrentActiveLayout
            CurrentActiveLayout := GetCurrentLayoutName()
            SetTimer(() => ToolTip(), -3000)
            return
        }
    }

    ; WORD MODE: No selection found, select current word
    ; Restore clipboard first since we're starting fresh
    A_Clipboard := oldClipboard

    ; Use last word selection from line
    SelectLastWordInLine()
    A_Clipboard := ""
    Send "^c"
    Sleep 200

    if (A_Clipboard != "" && Trim(A_Clipboard) != "") {
        wordText := Trim(A_Clipboard)

        ; Convert the word
        currentLayout := GetCurrentLayoutName()
        conversionResult := ConvertTextWithLayoutAwareness(wordText, currentLayout)

        if (conversionResult.text != "" && conversionResult.text != wordText) {
            ; Use clipboard method for word too
            A_Clipboard := conversionResult.text
            Send "^v"
            Sleep 100

            ; Restore clipboard
            A_Clipboard := oldClipboard

            ToolTip("WORD: '" . wordText . "' → '" . conversionResult.text . "'")
        } else {
            ; Restore clipboard and deselect
            A_Clipboard := oldClipboard
            Send "{Right}"
            ToolTip("No conversion for word")
        }
    } else {
        ; Restore clipboard
        A_Clipboard := oldClipboard
        ToolTip("No text found")
    }

    ; Switch layout
    SwitchToNextLayout()

    ; Update current layout tracking with retry logic
    global CurrentActiveLayout
    CurrentActiveLayout := GetCurrentLayoutNameWithRetry()

    SetTimer(() => ToolTip(), -3000)
}

; Regular CapsLock behavior (just switch layout)
CapsLock:: {
    SwitchToNextLayout()

    ; Update current layout tracking with retry logic
    global CurrentActiveLayout
    CurrentActiveLayout := GetCurrentLayoutNameWithRetry()

    ; Show current layout
    ToolTip("Layout: " . CurrentActiveLayout)
    SetTimer(() => ToolTip(), -1500)
}

; Hotkey to refresh layout mappings
^!r:: {
    ToolTip("Refreshing keyboard layouts...")
    InitializeLayouts()
}

; Hotkey to show current layout info
^!i:: {
    global AvailableLayouts, CurrentActiveLayout

    layoutInfo := "Current Layout: " . CurrentActiveLayout . "`n`nAvailable Layouts:`n"
    for layout in AvailableLayouts {
        indicator := (layout.name == CurrentActiveLayout) ? " ◄" : ""
        layoutInfo .= "• " . layout.friendlyName . " (" . layout.name . ")" . indicator . "`n"
    }

    ToolTip(layoutInfo)
    SetTimer(() => ToolTip(), -5000)
}
