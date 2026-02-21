## Screen and cursor operations.
##
## Provides functions for cursor movement, screen clearing,
## alternate screen buffer, mouse tracking, and other terminal control.

import types/screen
import constants/[escape, sequences]

export screen.EraseMode, screen.MouseMode, screen.CursorStyle
export screen.BracketedPasteState

# =============================================================================
# Cursor Movement
# =============================================================================

proc cursorUp*(n: int = 1): string =
  ## Move cursor up N lines.
  csi & $n & "A"

proc cursorDown*(n: int = 1): string =
  ## Move cursor down N lines.
  csi & $n & "B"

proc cursorForward*(n: int = 1): string =
  ## Move cursor forward N columns.
  csi & $n & "C"

proc cursorBack*(n: int = 1): string =
  ## Move cursor back N columns.
  csi & $n & "D"

proc cursorNextLine*(n: int = 1): string =
  ## Move cursor to beginning of line N lines down.
  csi & $n & "E"

proc cursorPrevLine*(n: int = 1): string =
  ## Move cursor to beginning of line N lines up.
  csi & $n & "F"

proc cursorColumn*(col: int): string =
  ## Move cursor to column (1-based).
  csi & $col & "G"

proc cursorPosition*(row, col: int): string =
  ## Move cursor to position (1-based).
  csi & $row & ";" & $col & "H"

proc moveCursor*(row, col: int): string {.inline.} =
  ## Alias for cursorPosition.
  cursorPosition(row, col)

proc cursorHome*(): string =
  ## Move cursor to home position (1,1).
  csi & "1;1H"


# =============================================================================
# Cursor Save/Restore
# =============================================================================

proc saveCursorPosition*(): string =
  ## Save cursor position (ANSI).
  SaveCursorSeq

proc restoreCursorPosition*(): string =
  ## Restore cursor position (ANSI).
  RestoreCursorSeq

proc saveCursorPositionDEC*(): string =
  ## Save cursor position (DEC private mode).
  SaveCursorDECSeq

proc restoreCursorPositionDEC*(): string =
  ## Restore cursor position (DEC private mode).
  RestoreCursorDECSeq


# =============================================================================
# Cursor Visibility & Style
# =============================================================================

proc showCursor*(): string =
  ## Show cursor.
  ShowCursorSeq

proc hideCursor*(): string =
  ## Hide cursor.
  HideCursorSeq

proc setCursorStyle*(style: CursorStyle): string =
  ## Set cursor style.
  csi & $ord(style) & " q"


# =============================================================================
# Screen Clearing
# =============================================================================

proc eraseDisplay*(mode: EraseMode = EraseMode.Entire): string =
  ## Erase display.
  csi & $ord(mode) & "J"

proc clearScreen*(): string =
  ## Clear entire screen and move cursor home.
  EraseScreenSeq & cursorHome()

proc clearToEnd*(): string =
  ## Clear from cursor to end of screen.
  EraseToEndSeq

proc clearToStart*(): string =
  ## Clear from start of screen to cursor.
  EraseToStartSeq

proc clearScrollback*(): string =
  ## Clear scrollback buffer.
  EraseScrollbackSeq

proc eraseLine*(mode: EraseMode = EraseMode.Entire): string =
  ## Erase line.
  csi & $ord(mode) & "K"

proc clearLine*(): string =
  ## Clear entire line.
  EraseEntireLineSeq

proc clearLineRight*(): string =
  ## Clear from cursor to end of line.
  EraseLineRightSeq

proc clearLineLeft*(): string =
  ## Clear from start of line to cursor.
  EraseLineLeftSeq

proc clearLines*(n: int): string =
  ## Clear N lines starting from current line, moving up.
  result = clearLine()
  for _ in 1..<n:
    result.add(cursorUp(1))
    result.add(clearLine())


# =============================================================================
# Scrolling
# =============================================================================

proc scrollUp*(n: int = 1): string =
  ## Scroll screen up N lines.
  csi & $n & "S"

proc scrollDown*(n: int = 1): string =
  ## Scroll screen down N lines.
  csi & $n & "T"

proc setScrollRegion*(top, bottom: int): string =
  ## Set scrolling region (1-based, inclusive).
  csi & $top & ";" & $bottom & "r"

proc resetScrollRegion*(): string =
  ## Reset scrolling region to full screen.
  ResetScrollRegionSeq


# =============================================================================
# Line Operations
# =============================================================================

proc insertLines*(n: int = 1): string =
  ## Insert N blank lines at cursor.
  csi & $n & "L"

proc deleteLines*(n: int = 1): string =
  ## Delete N lines at cursor.
  csi & $n & "M"

proc insertChars*(n: int = 1): string =
  ## Insert N blank characters at cursor.
  csi & $n & "@"

proc deleteChars*(n: int = 1): string =
  ## Delete N characters at cursor.
  csi & $n & "P"


# =============================================================================
# Alternate Screen Buffer
# =============================================================================

proc altScreen*(): string =
  ## Enter alternate screen buffer (saves main screen).
  AltScreenSeq

proc exitAltScreen*(): string =
  ## Exit alternate screen buffer (restores main screen).
  ExitAltScreenSeq

proc enableKittyKeys*(): string =
  ## Request kitty keyboard protocol (level 1).
  ## Disambiguates ctrl-i from Tab, ctrl-m from Enter, etc.
  ## Terminals that don't support KKP silently ignore this.
  "\x1b[>1u"

proc disableKittyKeys*(): string =
  ## Pop kitty keyboard protocol mode stack (restore terminal defaults).
  "\x1b[<u"

proc saveScreen*(): string =
  ## Save screen content (legacy).
  SaveScreenSeq

proc restoreScreen*(): string =
  ## Restore screen content (legacy).
  RestoreScreenSeq


# =============================================================================
# Mouse Tracking
# =============================================================================

proc enableMousePress*(): string =
  ## Enable X10 mouse mode (button press only).
  EnableMousePressSeq

proc disableMousePress*(): string =
  ## Disable X10 mouse mode.
  DisableMousePressSeq

proc enableMouse*(): string =
  ## Enable VT200 mouse mode (press and release).
  EnableMouseSeq

proc disableMouse*(): string =
  ## Disable VT200 mouse mode.
  DisableMouseSeq

proc enableMouseHilite*(): string =
  ## Enable VT200 highlight tracking.
  EnableMouseHiliteSeq

proc disableMouseHilite*(): string =
  ## Disable VT200 highlight tracking.
  DisableMouseHiliteSeq

proc enableMouseCellMotion*(): string =
  ## Enable button-event tracking (motion while pressed).
  EnableMouseCellMotionSeq

proc disableMouseCellMotion*(): string =
  ## Disable button-event tracking.
  DisableMouseCellMotionSeq

proc enableMouseAllMotion*(): string =
  ## Enable any-event tracking (all motion).
  EnableMouseAllMotionSeq

proc disableMouseAllMotion*(): string =
  ## Disable any-event tracking.
  DisableMouseAllMotionSeq

proc enableMouseSgr*(): string =
  ## Enable SGR extended mouse mode.
  EnableMouseSgrSeq

proc disableMouseSgr*(): string =
  ## Disable SGR extended mouse mode.
  DisableMouseSgrSeq

proc enableMousePixels*(): string =
  ## Enable SGR pixel mouse mode.
  EnableMousePixelsSeq

proc disableMousePixels*(): string =
  ## Disable SGR pixel mouse mode.
  DisableMousePixelsSeq


# =============================================================================
# Bracketed Paste
# =============================================================================

proc enableBracketedPaste*(): string =
  ## Enable bracketed paste mode.
  EnableBracketedPasteSeq

proc disableBracketedPaste*(): string =
  ## Disable bracketed paste mode.
  DisableBracketedPasteSeq


# =============================================================================
# Focus Events
# =============================================================================

proc enableFocusEvents*(): string =
  ## Enable focus in/out events.
  EnableFocusSeq

proc disableFocusEvents*(): string =
  ## Disable focus in/out events.
  DisableFocusSeq


# =============================================================================
# Window/Terminal Properties
# =============================================================================

proc setWindowTitle*(title: string): string =
  ## Set window title.
  osc & "2;" & title & $bel

proc setIconName*(name: string): string =
  ## Set icon name.
  osc & "1;" & name & $bel

proc setWindowTitleAndIcon*(title: string): string =
  ## Set both window title and icon name.
  osc & "0;" & title & $bel


# =============================================================================
# Terminal Colors
# =============================================================================

proc setTermForeground*(color: string): string =
  ## Set terminal foreground color (color is hex or name).
  osc & "10;" & color & $bel

proc setTermBackground*(color: string): string =
  ## Set terminal background color.
  osc & "11;" & color & $bel

proc setTermCursorColor*(color: string): string =
  ## Set terminal cursor color.
  osc & "12;" & color & $bel

proc queryTermForeground*(): string =
  ## Query terminal foreground color.
  QueryForegroundColorSeq

proc queryTermBackground*(): string =
  ## Query terminal background color.
  QueryBackgroundColorSeq

proc queryTermCursorColor*(): string =
  ## Query terminal cursor color.
  QueryCursorColorSeq


# =============================================================================
# Reset
# =============================================================================

proc reset*(): string =
  ## Reset all text attributes.
  resetSeq

proc softReset*(): string =
  ## Soft terminal reset (DECSTR).
  csi & "!p"

proc hardReset*(): string =
  ## Full terminal reset (RIS).
  "\x1bc"
