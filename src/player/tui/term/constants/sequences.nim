## Screen and cursor escape sequence templates.
##
## These are format strings that can be used with strformat or strutils.format
## to generate complete escape sequences.

import escape

const
  # Cursor movement (csi sequences)
  CursorUpSeq* = csi & "$1A"           ## Move cursor up N lines
  CursorDownSeq* = csi & "$1B"         ## Move cursor down N lines
  CursorForwardSeq* = csi & "$1C"      ## Move cursor forward N columns
  CursorBackSeq* = csi & "$1D"         ## Move cursor back N columns
  CursorNextLineSeq* = csi & "$1E"     ## Move to beginning of line N down
  CursorPrevLineSeq* = csi & "$1F"     ## Move to beginning of line N up
  CursorColumnSeq* = csi & "$1G"       ## Move to column N
  CursorPositionSeq* = csi & "$1;$2H"  ## Move to row;col

  # Cursor save/restore
  SaveCursorSeq* = csi & "s"           ## Save cursor position
  RestoreCursorSeq* = csi & "u"        ## Restore cursor position
  SaveCursorDECSeq* = "\x1b7"          ## Save cursor (DEC private)
  RestoreCursorDECSeq* = "\x1b8"       ## Restore cursor (DEC private)

  # Cursor visibility
  ShowCursorSeq* = csi & "?25h"        ## Show cursor
  HideCursorSeq* = csi & "?25l"        ## Hide cursor

  # Cursor style (DECSCUSR)
  CursorStyleSeq* = csi & "$1 q"       ## Set cursor style

  # Screen erase
  EraseDisplaySeq* = csi & "$1J"       ## Erase display (mode 0-2)
  EraseLineSeq* = csi & "$1K"          ## Erase line (mode 0-2)

  # Specific erase shortcuts
  EraseToEndSeq* = csi & "0J"          ## Erase to end of screen
  EraseToStartSeq* = csi & "1J"        ## Erase to start of screen
  EraseScreenSeq* = csi & "2J"         ## Erase entire screen
  EraseScrollbackSeq* = csi & "3J"     ## Erase scrollback buffer

  EraseLineRightSeq* = csi & "0K"      ## Erase from cursor to end of line
  EraseLineLeftSeq* = csi & "1K"       ## Erase from start of line to cursor
  EraseEntireLineSeq* = csi & "2K"     ## Erase entire line

  # Scrolling
  ScrollUpSeq* = csi & "$1S"           ## Scroll up N lines
  ScrollDownSeq* = csi & "$1T"         ## Scroll down N lines
  ScrollRegionSeq* = csi & "$1;$2r"    ## Set scroll region (top;bottom)
  ResetScrollRegionSeq* = csi & "r"    ## Reset scroll region

  # Line insertion/deletion
  InsertLineSeq* = csi & "$1L"         ## Insert N lines
  DeleteLineSeq* = csi & "$1M"         ## Delete N lines
  InsertCharSeq* = csi & "$1@"         ## Insert N characters
  DeleteCharSeq* = csi & "$1P"         ## Delete N characters

  # Alternate screen buffer
  AltScreenSeq* = csi & "?1049h"       ## Enter alternate screen
  ExitAltScreenSeq* = csi & "?1049l"   ## Exit alternate screen
  SaveScreenSeq* = csi & "?47h"        ## Save screen (legacy)
  RestoreScreenSeq* = csi & "?47l"     ## Restore screen (legacy)

  # Mouse tracking
  EnableMousePressSeq* = csi & "?9h"         ## X10 mouse
  DisableMousePressSeq* = csi & "?9l"
  EnableMouseSeq* = csi & "?1000h"           ## VT200 mouse
  DisableMouseSeq* = csi & "?1000l"
  EnableMouseHiliteSeq* = csi & "?1001h"     ## VT200 highlight
  DisableMouseHiliteSeq* = csi & "?1001l"
  EnableMouseCellMotionSeq* = csi & "?1002h" ## Button-event tracking
  DisableMouseCellMotionSeq* = csi & "?1002l"
  EnableMouseAllMotionSeq* = csi & "?1003h"  ## Any-event tracking
  DisableMouseAllMotionSeq* = csi & "?1003l"
  EnableMouseSgrSeq* = csi & "?1006h"        ## SGR extended mode
  DisableMouseSgrSeq* = csi & "?1006l"
  EnableMousePixelsSeq* = csi & "?1016h"     ## SGR pixels mode
  DisableMousePixelsSeq* = csi & "?1016l"

  # Bracketed paste
  EnableBracketedPasteSeq* = csi & "?2004h"
  DisableBracketedPasteSeq* = csi & "?2004l"
  BracketedPasteStartSeq* = csi & "200~"
  BracketedPasteEndSeq* = csi & "201~"

  # Focus events
  EnableFocusSeq* = csi & "?1004h"
  DisableFocusSeq* = csi & "?1004l"

  # osc sequences (Operating System Commands)
  SetWindowTitleSeq* = osc & "2;$1" & bel    ## Set window title
  SetIconNameSeq* = osc & "1;$1" & bel       ## Set icon name
  SetBothTitleSeq* = osc & "0;$1" & bel      ## Set both title and icon

  # Terminal colors (osc 10-19)
  SetForegroundColorSeq* = osc & "10;$1" & bel
  SetBackgroundColorSeq* = osc & "11;$1" & bel
  SetCursorColorSeq* = osc & "12;$1" & bel
  QueryForegroundColorSeq* = osc & "10;?" & bel
  QueryBackgroundColorSeq* = osc & "11;?" & bel
  QueryCursorColorSeq* = osc & "12;?" & bel

  # osc 52 - Clipboard
  ClipboardSetSeq* = osc & "52;$1;$2" & bel  ## $1=target, $2=base64 data
  ClipboardClearSeq* = osc & "52;$1;" & bel

  # osc 8 - Hyperlinks
  HyperlinkStartSeq* = osc & "8;$1;$2" & bel ## $1=params, $2=URL
  HyperlinkEndSeq* = osc & "8;;" & bel

  # osc 777 - Notifications (iTerm2, some other terminals)
  NotifySeq* = osc & "777;notify;$1;$2" & bel  ## $1=title, $2=body

  # osc 9 - Notifications (ConEmu, Windows Terminal)
  NotifyConEmuSeq* = osc & "9;$1" & bel

  # Device status reports
  DeviceStatusReportSeq* = csi & "6n"        ## Query cursor position
  DeviceAttributesSeq* = csi & "c"           ## Query device attributes
