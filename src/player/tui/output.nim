## TUI output
##
## Handles rendering the cell buffer to the terminal.

import std/[strutils, unicode]

import ../tui/buffer
import ../tui/term/term
import ../tui/styles/ec_palette

proc borderRoleColorForProfile(c: Color, profile: Profile): Color =
  ## Preserve border-role contrast in lower-color profiles.
  if c.kind != ColorKind.Rgb:
    return convert(c, profile)

  let rgb = c.rgb
  case profile
  of Profile.Ansi:
    if rgb == PrimaryBorderColor:
      return color(AnsiColor(4))
    if rgb == SecondaryBorderColor:
      return color(AnsiColor(8))
    if rgb == TableBorderColor:
      return color(AnsiColor(14))
    return convert(c, profile)
  of Profile.Ansi256:
    if rgb == PrimaryBorderColor:
      return color(Ansi256Color(19))
    if rgb == SecondaryBorderColor:
      return color(Ansi256Color(60))
    if rgb == TableBorderColor:
      return color(Ansi256Color(103))
    return convert(c, profile)
  else:
    convert(c, profile)

proc styleForProfile(style: CellStyle, profile: Profile): CellStyle =
  ## Convert style colors to terminal profile while preserving border roles.
  result = style
  result.fg = borderRoleColorForProfile(style.fg, profile)
  result.bg = borderRoleColorForProfile(style.bg, profile)

proc outputBuffer*(buf: var CellBuffer) =
  ## Output buffer to terminal with proper ANSI escape sequences
  let profile = detectProfile()
  var lastStyle = defaultStyle()

  for y in 0 ..< buf.h:
    var x = 0
    while x < buf.w:
      if not buf.dirty(x, y):
        x += 1
        continue

      # Position cursor at start of dirty run (1-based ANSI coordinates)
      stdout.write("\e[", y + 1, ";", x + 1, "H")

      while x < buf.w and buf.dirty(x, y):
        let (rune, style, _) = buf.getRune(x, y)
        let emitStyle = styleForProfile(style, profile)

        # Only emit style changes when needed (optimization)
        if emitStyle != lastStyle:
          # Build ANSI SGR codes
          var codes: seq[string] = @[]

          # Reset if needed
          if emitStyle.fg.isNone and emitStyle.bg.isNone and
              emitStyle.attrs.len == 0:
            stdout.write("\e[0m")
          else:
            # Attributes
            if StyleAttr.Bold in emitStyle.attrs:
              codes.add("1")
            if StyleAttr.Italic in emitStyle.attrs:
              codes.add("3")
            if StyleAttr.Underline in emitStyle.attrs:
              codes.add("4")

            # Foreground color (24-bit RGB)
            if emitStyle.fg.kind == ColorKind.Rgb:
              let rgb = emitStyle.fg.rgb
              codes.add("38;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
            elif emitStyle.fg.kind == ColorKind.Ansi256:
              codes.add("38;5;" & $int(emitStyle.fg.ansi256))
            elif emitStyle.fg.kind == ColorKind.Ansi:
              let code = int(emitStyle.fg.ansi)
              if code < 8:
                codes.add($(30 + code))
              else:
                codes.add($(90 + code - 8))

            # Background color (24-bit RGB)
            if emitStyle.bg.kind == ColorKind.Rgb:
              let rgb = emitStyle.bg.rgb
              codes.add("48;2;" & $rgb.r & ";" & $rgb.g & ";" & $rgb.b)
            elif emitStyle.bg.kind == ColorKind.Ansi256:
              codes.add("48;5;" & $int(emitStyle.bg.ansi256))
            elif emitStyle.bg.kind == ColorKind.Ansi:
              let code = int(emitStyle.bg.ansi)
              if code < 8:
                codes.add($(40 + code))
              else:
                codes.add($(100 + code - 8))

            # Emit codes
            if codes.len > 0:
              stdout.write("\e[0m\e[", codes.join(";"), "m")

          lastStyle = emitStyle

        if rune.int < 0x80:
          stdout.write(char(rune.int))
        else:
          stdout.write(rune.toUTF8)
        buf.setDirty(x, y, false)
        x += 1

  # Reset at end
  stdout.write("\e[0m")
  stdout.flushFile()
