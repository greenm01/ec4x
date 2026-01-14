import ../../src/player/tui/term/term

## Port of termenv/examples/hello-world/main.go
##
## This demonstrates the termenv library's styling capabilities.
## Run with: nim c -r tests/term/texamples.nim

var output = newStdoutOutput()

# Profile detection
let profile = detectProfile()

echo "\t", output.newStyle("bold").bold()
echo "\t", output.newStyle("faint").faint()
echo "\t", output.newStyle("italic").italic()
echo "\t", output.newStyle("underline").underline()
echo "\t", output.newStyle("crossout").crossOut()

# Rainbow foreground colors
echo "\t",
  output.newStyle("red").fg(profile.color("#E88388")), " ",
  output.newStyle("green").fg(profile.color("#A8CC8C")), " ",
  output.newStyle("yellow").fg(profile.color("#DBAB79")), " ",
  output.newStyle("blue").fg(profile.color("#71BEF2")), " ",
  output.newStyle("magenta").fg(profile.color("#D290E4")), " ",
  output.newStyle("cyan").fg(profile.color("#66C2CD")), " ",
  output.newStyle("gray").fg(profile.color("#B9BFCA"))

# Rainbow background colors (with black foreground)
echo "\t",
  output.newStyle("red").fg("0").bg(profile.color("#E88388")), " ",
  output.newStyle("green").fg("0").bg(profile.color("#A8CC8C")), " ",
  output.newStyle("yellow").fg("0").bg(profile.color("#DBAB79")), " ",
  output.newStyle("blue").fg("0").bg(profile.color("#71BEF2")), " ",
  output.newStyle("magenta").fg("0").bg(profile.color("#D290E4")), " ",
  output.newStyle("cyan").fg("0").bg(profile.color("#66C2CD")), " ",
  output.newStyle("gray").fg("0").bg(profile.color("#B9BFCA"))

echo ""

# System info
echo "\t", output.newStyle("Has foreground color").bold(), " ", noColor()  # TODO: foregroundColor()
echo "\t", output.newStyle("Has background color").bold(), " ", noColor()  # TODO: backgroundColor()
echo "\t", output.newStyle("Has dark background?").bold(), " ", output.hasDarkBackground()
echo ""

# Clipboard demo
let hw = "Hello, world!"
output.copy(hw)  # TODO: Implement clipboard
echo "\t", "\"", hw, "\"", " copied to clipboard"
echo ""

# Notification demo
output.notify("Termenv", hw)  # TODO: Implement notifications
echo "\tTriggered a notification"
echo ""

# Hyperlink demo
echo "\t", output.hyperlink("http://example.com", "This is a link")
echo ""