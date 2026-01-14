## ANSI escape sequence constants.
##
## Defines the fundamental escape sequence building blocks used
## throughout the terminal library.

const
  # Basic escape characters
  ESC* = '\x1b'              ## Escape character
  BEL* = '\a'                ## Bell character
  CSI* = "\x1b["             ## Control Sequence Introducer
  OSC* = "\x1b]"             ## Operating System Command
  ST* = "\x1b\\"             ## String Terminator
  DCS* = "\x1bP"             ## Device Control String
  APC* = "\x1b_"             ## Application Program Command

  # Reset sequence
  ResetSeq* = CSI & "0m"     ## Reset all attributes

  # SGR (Select Graphic Rendition) parameters
  SgrForeground* = "38"      ## Foreground color prefix
  SgrBackground* = "48"      ## Background color prefix

  # Style sequences (SGR parameters)
  SgrReset* = "0"
  SgrBold* = "1"
  SgrFaint* = "2"
  SgrItalic* = "3"
  SgrUnderline* = "4"
  SgrBlink* = "5"
  SgrReverse* = "7"
  SgrCrossOut* = "9"
  SgrOverline* = "53"

  # Style reset sequences
  SgrBoldOff* = "22"         ## Also resets faint
  SgrItalicOff* = "23"
  SgrUnderlineOff* = "24"
  SgrBlinkOff* = "25"
  SgrReverseOff* = "27"
  SgrCrossOutOff* = "29"
  SgrOverlineOff* = "55"
