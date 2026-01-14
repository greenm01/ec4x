## Screen and cursor escape sequence templates.
##
## These are format strings that can be used with strformat or strutils.format
## to generate complete escape sequences.

import escape

const
  # Cursor movement (CSI sequences)
  CursorUpSeq* = CSI & "$1A"           ## Move cursor up N lines
  CursorDownSeq* = CSI & "$1B"         ## Move cursor down N lines
  CursorForwardSeq* = CSI & "$1C"      ## Move cursor forward N columns
  CursorBackSeq* = CSI & "$1D"         ## Move cursor back N columns
  CursorNextLineSeq* = CSI & "$1E"     ## Move to beginning of line N down
  CursorPrevLineSeq* = CSI & "$1F"     ## Move to beginning of line N up
  CursorColumnSeq* = CSI & "$1G"       ## Move to column N
  CursorPositionSeq* = CSI & "$1;$2H"  ## Move to row;col

  # Cursor save/restore
  SaveCursorSeq* = CSI & "s"           ## Save cursor position
  RestoreCursorSeq* = CSI & "u"        ## Restore cursor position
  SaveCursorDECSeq* = "\x1b7"          ## Save cursor (DEC private)
  RestoreCursorDECSeq* = "\x1b8"       ## Restore cursor (DEC private)

  # Cursor visibility
  ShowCursorSeq* = CSI & "?25h"        ## Show cursor
  HideCursorSeq* = CSI & "?25l"        ## Hide cursor

  # Cursor style (DECSCUSR)
  CursorStyleSeq* = CSI & "$1 q"       ## Set cursor style

  # Screen erase
  EraseDisplaySeq* = CSI & "$1J"       ## Erase display (mode 0-2)
  EraseLineSeq* = CSI & "$1K"          ## Erase line (mode 0-2)

  # Specific erase shortcuts
  EraseToEndSeq* = CSI & "0J"          ## Erase to end of screen
  EraseToStartSeq* = CSI & "1J"        ## Erase to start of screen
  EraseScreenSeq* = CSI & "2J"         ## Erase entire screen
  EraseScrollbackSeq* = CSI & "3J"     ## Erase scrollback buffer

  EraseLineRightSeq* = CSI & "0K"      ## Erase from cursor to end of line
  EraseLineLeftSeq* = CSI & "1K"       ## Erase from start of line to cursor
  EraseEntireLineSeq* = CSI & "2K"     ## Erase entire line

  # Scrolling
  ScrollUpSeq* = CSI & "$1S"           ## Scroll up N lines
  ScrollDownSeq* = CSI & "$1T"         ## Scroll down N lines
  ScrollRegionSeq* = CSI & "$1;$2r"    ## Set scroll region (top;bottom)
  ResetScrollRegionSeq* = CSI & "r"    ## Reset scroll region

  # Line insertion/deletion
  InsertLineSeq* = CSI & "$1L"         ## Insert N lines
  DeleteLineSeq* = CSI & "$1M"         ## Delete N lines
  InsertCharSeq* = CSI & "$1@"         ## Insert N characters
  DeleteCharSeq* = CSI & "$1P"         ## Delete N characters

  # Alternate screen buffer
  AltScreenSeq* = CSI & "?1049h"       ## Enter alternate screen
  ExitAltScreenSeq* = CSI & "?1049l"   ## Exit alternate screen
  SaveScreenSeq* = CSI & "?47h"        ## Save screen (legacy)
  RestoreScreenSeq* = CSI & "?47l"     ## Restore screen (legacy)

  # Mouse tracking
  EnableMousePressSeq* = CSI & "?9h"         ## X10 mouse
  DisableMousePressSeq* = CSI & "?9l"
  EnableMouseSeq* = CSI & "?1000h"           ## VT200 mouse
  DisableMouseSeq* = CSI & "?1000l"
  EnableMouseHiliteSeq* = CSI & "?1001h"     ## VT200 highlight
  DisableMouseHiliteSeq* = CSI & "?1001l"
  EnableMouseCellMotionSeq* = CSI & "?1002h" ## Button-event tracking
  DisableMouseCellMotionSeq* = CSI & "?1002l"
  EnableMouseAllMotionSeq* = CSI & "?1003h"  ## Any-event tracking
  DisableMouseAllMotionSeq* = CSI & "?1003l"
  EnableMouseSgrSeq* = CSI & "?1006h"        ## SGR extended mode
  DisableMouseSgrSeq* = CSI & "?1006l"
  EnableMousePixelsSeq* = CSI & "?1016h"     ## SGR pixels mode
  DisableMousePixelsSeq* = CSI & "?1016l"

  # Bracketed paste
  EnableBracketedPasteSeq* = CSI & "?2004h"
  DisableBracketedPasteSeq* = CSI & "?2004l"
  BracketedPasteStartSeq* = CSI & "200~"
  BracketedPasteEndSeq* = CSI & "201~"

  # Focus events
  EnableFocusSeq* = CSI & "?1004h"
  DisableFocusSeq* = CSI & "?1004l"

  # OSC sequences (Operating System Commands)
  SetWindowTitleSeq* = OSC & "2;$1" & BEL    ## Set window title
  SetIconNameSeq* = OSC & "1;$1" & BEL       ## Set icon name
  SetBothTitleSeq* = OSC & "0;$1" & BEL      ## Set both title and icon

  # Terminal colors (OSC 10-19)
  SetForegroundColorSeq* = OSC & "10;$1" & BEL
  SetBackgroundColorSeq* = OSC & "11;$1" & BEL
  SetCursorColorSeq* = OSC & "12;$1" & BEL
  QueryForegroundColorSeq* = OSC & "10;?" & BEL
  QueryBackgroundColorSeq* = OSC & "11;?" & BEL
  QueryCursorColorSeq* = OSC & "12;?" & BEL

  # OSC 52 - Clipboard
  ClipboardSetSeq* = OSC & "52;$1;$2" & BEL  ## $1=target, $2=base64 data
  ClipboardClearSeq* = OSC & "52;$1;" & BEL

  # OSC 8 - Hyperlinks
  HyperlinkStartSeq* = OSC & "8;$1;$2" & BEL ## $1=params, $2=URL
  HyperlinkEndSeq* = OSC & "8;;" & BEL

  # OSC 777 - Notifications (iTerm2, some other terminals)
  NotifySeq* = OSC & "777;notify;$1;$2" & BEL  ## $1=title, $2=body

  # OSC 9 - Notifications (ConEmu, Windows Terminal)
  NotifyConEmuSeq* = OSC & "9;$1" & BEL

  # Device status reports
  DeviceStatusReportSeq* = CSI & "6n"        ## Query cursor position
  DeviceAttributesSeq* = CSI & "c"           ## Query device attributes
