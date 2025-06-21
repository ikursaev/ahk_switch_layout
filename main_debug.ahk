#Requires AutoHotkey v2.0

SetCapsLockState "AlwaysOff"

; Test hotkey with debugging
^CapsLock:: {
    ; Save current clipboard
    oldClipboard := ClipboardAll()

    ; METHOD 1: Try to detect selection without copying first
    ; Use Windows API to get selection info

    ; Clear clipboard
    A_Clipboard := ""

    ; Try copying
    Send "^c"
    Sleep 300  ; Longer wait

    ; Check what we got
    copiedText := A_Clipboard

    if (copiedText != "" && Trim(copiedText) != "") {
        ; We got something - this means there was a selection
        MsgBox("FOUND SELECTION: '" . copiedText . "'`nLength: " . StrLen(copiedText) . " characters")

        ; The text is still selected, so we can just replace it
        convertedText := "CONVERTED_" . copiedText . "_CONVERTED"
        Send convertedText

    } else {
        ; No selection - select current word
        MsgBox("NO SELECTION FOUND - selecting current word")

        Send "^{Left}"
        Send "^+{Right}"
        A_Clipboard := ""
        Send "^c"
        Sleep 200

        wordText := A_Clipboard
        if (wordText != "" && Trim(wordText) != "") {
            MsgBox("SELECTED WORD: '" . wordText . "'")
            convertedWord := "CONVERTED_" . wordText . "_CONVERTED"
            Send convertedWord
        } else {
            MsgBox("FAILED TO SELECT WORD")
        }
    }

    ; Restore clipboard
    A_Clipboard := oldClipboard
}

; Test hotkey to show current selection status
^!t:: {
    ; Save clipboard
    oldClip := A_Clipboard
    A_Clipboard := ""

    ; Try to copy
    Send "^c"
    Sleep 100

    if (A_Clipboard != "") {
        MsgBox("Current selection: '" . A_Clipboard . "'")
    } else {
        MsgBox("No text currently selected")
    }

    ; Restore
    A_Clipboard := oldClip
}