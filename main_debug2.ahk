#Requires AutoHotkey v2.0

SetCapsLockState "AlwaysOff"

; Simple test to see what's happening with text conversion
^CapsLock:: {
    ; Save clipboard
    oldClipboard := ClipboardAll()

    ; Clear and copy
    A_Clipboard := ""
    Send "^c"
    Sleep 300

    if (A_Clipboard != "" && Trim(A_Clipboard) != "") {
        selectedText := Trim(A_Clipboard)

        ; Show what we got
        MsgBox("STEP 1 - Got text: '" . selectedText . "'`nLength: " . StrLen(selectedText) . " characters")

        ; Simple character-by-character conversion test
        result := ""
        Loop Parse, selectedText {
            char := A_LoopField
            ; Simple test: convert 'h' to 'H', 'o' to 'O', etc.
            if (char = "h") {
                result .= "H"
            } else if (char = "o") {
                result .= "O"
            } else if (char = "w") {
                result .= "W"
            } else if (char = " ") {
                result .= " "
            } else if (char = "a") {
                result .= "A"
            } else if (char = "r") {
                result .= "R"
            } else if (char = "e") {
                result .= "E"
            } else if (char = "y") {
                result .= "Y"
            } else if (char = "u") {
                result .= "U"
            } else {
                result .= char
            }
        }

        ; Show what we converted
        MsgBox("STEP 2 - Converted to: '" . result . "'`nLength: " . StrLen(result) . " characters")

        ; Replace the text
        Send result

        MsgBox("STEP 3 - Sent converted text")

    } else {
        MsgBox("No text was selected")
    }

    ; Restore clipboard
    A_Clipboard := oldClipboard
}