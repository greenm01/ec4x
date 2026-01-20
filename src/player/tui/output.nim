## TUI output
##
## Handles rendering the cell buffer to the terminal.

import std/[strutils]

import ../tui/buffer
import ../tui/term/term

proc outputBuffer*(buf: CellBuffer) =
  ## Output buffer to terminal with proper ANSI escape sequences
  var lastStyle = defaultStyle()

  for y in 0 ..< buf.h:
    # Position cursor at start of line (1-based ANSI coordinates)
    stdout.write("\e[", y + 1, ";1H")

    for x in 0 ..< buf.w:
      let (str, style, _) = buf.get(x, y)

      # Only emit style changes when needed (optimization)
      if style != lastStyle:
        # Build ANSI SGR codes
        var codes: seq[string] = @[]

        # Reset if needed
        if style.fg.isNone and style.bg.isNone and style.attrs.len == 0:
          stdout.write("\e[0m")
        else:
          # Attributes
          if StyleAttr.Bold in style.attrs:
            codes.add("1")
          if StyleAttr.Italic in style.attrs:
            codes.add("3")
          if StyleAttr.Underline in style.attrs:
            codes.add("4")

          # Foreground color (24-bit RGB)
          if style.fg.kind == ColorKind.Rgb:
            let rgb = style.fg.rgb
            codes.add("38;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
          elif style.fg.kind == ColorKind.Ansi256:
            codes.add("38;5;" & $int(style.fg.ansi256))
          elif style.fg.kind == ColorKind.Ansi:
            codes.add("38;5;" & $int(style.fg.ansi))

          # Background color (24-bit RGB)
          if style.bg.kind == ColorKind.Rgb:
            let rgb = style.bg.rgb
            codes.add("48;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
          elif style.bg.kind == ColorKind.Ansi256:
            codes.add("48;5;" & $int(style.bg.ansi256))
          elif style.bg.kind == ColorKind.Ansi:
            codes.add("48;5;" & $int(style.bg.ansi))

          # Emit codes
          if codes.len > 0:
            stdout.write("\e[0m\e[", codes.join(";"), "m")

        lastStyle = style

      stdout.write(str)

  # Reset at end
  stdout.write("\e[0m")
  stdout.flushFile()
