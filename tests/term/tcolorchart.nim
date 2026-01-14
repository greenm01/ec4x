## Color chart example - port of termenv/examples/color-chart
##
## Run with: nim c -r tests/term/tcolorchart.nim

import std/strformat
import ../../src/player/tui/term/term
import ../../src/player/tui/term/constants/ansi

var output = newStdoutOutput()

# Basic ANSI colors 0-15
echo output.newStyle("Basic ANSI colors").bold()

let p_ansi = Profile.Ansi
for i in 0..15:
  if i mod 8 == 0:
    echo ""

  # Background color
  let bg = color(AnsiColor(i))
  let hexVal = toHex(AnsiColor(i))
  
  # Create styled text
  var s = output.newStyle(&" {i:2} {hexVal} ")
  
  # Set foreground (white for dark colors, black for light)
  if i < 5:
    s = s.fg(color(AnsiColor(7)))  # White
  else:
    s = s.fg(color(AnsiColor(0)))  # Black
  
  s = s.bg(bg)
  
  stdout.write($s)

echo "\n"

# Extended ANSI colors 16-231
echo output.newStyle("Extended ANSI colors").bold()

let p_256 = Profile.Ansi256
for i in 16..231:
  if (i - 16) mod 6 == 0:
    echo ""

  # Background color
  let bg = color(Ansi256Color(i))
  let hexVal = toHex(Ansi256Color(i))
  
  # Create styled text
  var s = output.newStyle(&" {i:3} {hexVal} ")
  
  # Set foreground
  if i < 28:
    s = s.fg(color(AnsiColor(7)))  # White
  else:
    s = s.fg(color(AnsiColor(0)))  # Black
  
  s = s.bg(bg)
  
  stdout.write($s)

echo "\n"

# Grayscale ANSI colors 232-255
echo output.newStyle("Extended ANSI Grayscale").bold()

for i in 232..255:
  if (i - 232) mod 6 == 0:
    echo ""

  # Background color
  let bg = color(Ansi256Color(i))
  let hexVal = toHex(Ansi256Color(i))
  
  # Create styled text
  var s = output.newStyle(&" {i:3} {hexVal} ")
  
  # Set foreground
  if i < 244:
    s = s.fg(color(AnsiColor(7)))  # White
  else:
    s = s.fg(color(AnsiColor(0)))  # Black
  
  s = s.bg(bg)
  
  stdout.write($s)

echo "\n"
