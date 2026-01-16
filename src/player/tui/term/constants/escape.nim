## ANSI escape sequence constants.
##
## Defines the fundamental escape sequence building blocks used
## throughout the terminal library.

const
  # Basic escape characters
  esc* = '\x1b'              ## Escape character
  bel* = '\a'                ## Bell character
  csi* = "\x1b["             ## Control Sequence Introducer
  osc* = "\x1b]"             ## Operating System Command
  st* = "\x1b\\"             ## String Terminator
  dcs* = "\x1bP"             ## Device Control String
  apc* = "\x1b_"             ## Application Program Command

  # Reset sequence
  resetSeq* = csi & "0m"     ## Reset all attributes

  # SGR (Select Graphic Rendition) parameters
  sgrForeground* = "38"      ## Foreground color prefix
  sgrBackground* = "48"      ## Background color prefix

  # Style sequences (SGR parameters)
  sgrReset* = "0"
  sgrBold* = "1"
  sgrFaint* = "2"
  sgrItalic* = "3"
  sgrUnderline* = "4"
  sgrBlink* = "5"
  sgrReverse* = "7"
  sgrCrossOut* = "9"
  sgrOverline* = "53"

  # Style reset sequences
  sgrBoldOff* = "22"         ## Also resets faint
  sgrItalicOff* = "23"
  sgrUnderlineOff* = "24"
  sgrBlinkOff* = "25"
  sgrReverseOff* = "27"
  sgrCrossOutOff* = "29"
  sgrOverlineOff* = "55"
