## TUI Launcher - Launch TUI in properly-sized terminal window
##
## Detects available terminal emulators and launches the TUI binary
## in a new window with optimal dimensions (120x36).
##
## If no suitable terminal is found, runs in current terminal with
## a size check and warning.

import std/[os, osproc, strformat, strutils]

when not defined(windows):
  import std/posix

const
  OptimalWidth* = 120
  OptimalHeight* = 36
  MinWidth* = 80
  MinHeight* = 24

type
  TerminalEmulator* {.pure.} = enum
    ## Supported terminal emulators
    Foot         # Wayland-native, fast
    Ghostty      # GPU-accelerated, modern
    WezTerm      # GPU-accelerated, feature-rich
    Alacritty    # GPU-accelerated, minimalist
    Kitty        # GPU-accelerated, feature-rich
    GnomeTerminal
    Konsole
    Xterm
    TerminalApp  # macOS
    None

proc detectTerminal*(): TerminalEmulator =
  ## Detect available terminal emulator
  ## Prioritizes modern GPU-accelerated terminals
  
  # Modern terminals (GPU-accelerated, excellent performance)
  if findExe("foot") != "":
    return TerminalEmulator.Foot
  
  if findExe("ghostty") != "":
    return TerminalEmulator.Ghostty
  
  if findExe("wezterm") != "":
    return TerminalEmulator.WezTerm
  
  if findExe("alacritty") != "":
    return TerminalEmulator.Alacritty
  
  if findExe("kitty") != "":
    return TerminalEmulator.Kitty
  
  # Traditional terminals
  if findExe("gnome-terminal") != "":
    return TerminalEmulator.GnomeTerminal
  
  if findExe("konsole") != "":
    return TerminalEmulator.Konsole
  
  if findExe("xterm") != "":
    return TerminalEmulator.Xterm
  
  # macOS
  when defined(macosx):
    if findExe("osascript") != "":
      return TerminalEmulator.TerminalApp
  
  return TerminalEmulator.None

proc launchInNewWindow*(binaryPath: string, args: seq[string] = @[],
                        width: int = OptimalWidth,
                        height: int = OptimalHeight): bool =
  ## Launch the TUI binary in a new terminal window
  ## Returns true if successfully launched in new window, false if fallback needed
  let childArgs = @[binaryPath] & args
  let terminal = detectTerminal()

  case terminal
  of TerminalEmulator.Foot:
    let termArgs = @[&"--window-size-chars={width}x{height}"] & childArgs
    discard startProcess("foot", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.Ghostty:
    when defined(macosx):
      # macOS: Ghostty CLI doesn't support launching terminal, use 'open' command
      # Build command line for -e flag
      var cmdLine = ""
      for i, arg in childArgs:
        if i > 0:
          cmdLine.add(" ")
        cmdLine.add(arg.quoteShell)
      
      let termArgs = @["-na", "Ghostty", "--args", "-e", cmdLine]
      discard startProcess("open", args = termArgs,
                           options = {poUsePath, poParentStreams})
      return true
    else:
      # Linux: Ghostty CLI works directly
      let termArgs = @["-e"] & childArgs
      discard startProcess("ghostty", args = termArgs,
                           options = {poUsePath, poParentStreams})
      return true

  of TerminalEmulator.WezTerm:
    # WezTerm uses a config override approach
    let termArgs = @["start", "--position", "0,0", "--"] & childArgs
    # Note: WezTerm doesn't easily support CLI geometry, rely on user config
    discard startProcess("wezterm", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.GnomeTerminal:
    let termArgs = @[&"--geometry={width}x{height}", "--"] & childArgs
    discard startProcess("gnome-terminal", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.Konsole:
    let termArgs = @["--geometry", &"{width}x{height}", "-e"] & childArgs
    discard startProcess("konsole", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.Xterm:
    let termArgs = @["-geometry", &"{width}x{height}", "-e"] & childArgs
    discard startProcess("xterm", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.Alacritty:
    let termArgs = @[
      "--option", &"window.dimensions.columns={width}",
      "--option", &"window.dimensions.lines={height}",
      "-e"
    ] & childArgs
    discard startProcess("alacritty", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.Kitty:
    let termArgs = @[
      &"--override", &"initial_window_width={width}c",
      "--override", &"initial_window_height={height}c"
    ] & childArgs
    discard startProcess("kitty", args = termArgs,
                         options = {poUsePath, poParentStreams})
    return true

  of TerminalEmulator.TerminalApp:
    # macOS Terminal.app via AppleScript
    var cmdLine = binaryPath.quoteShell
    for arg in args:
      cmdLine.add(" ")
      cmdLine.add(arg.quoteShell)
    let script = &"""
tell application "Terminal"
  activate
  set newTab to do script "cd '{getCurrentDir()}' && {cmdLine}"
  set number of columns of window 1 to {width}
  set number of rows of window 1 to {height}
end tell
"""
    discard execCmd(&"osascript -e {script.quoteShell}")
    return true
  
  of TerminalEmulator.None:
    return false

proc getCurrentTerminalSize*(): tuple[width, height: int] =
  ## Get current terminal size using tput
  ## Returns (0, 0) if unable to detect
  result = (0, 0)
  
  try:
    let colsStr = execProcess("tput cols").strip()
    let rowsStr = execProcess("tput lines").strip()
    result.width = parseInt(colsStr)
    result.height = parseInt(rowsStr)
  except:
    discard

proc isTerminalSizeOk*(width, height: int): tuple[ok: bool, msg: string] =
  ## Check if terminal size is adequate
  if width < MinWidth or height < MinHeight:
    return (false, &"Terminal too small ({width}x{height}). Minimum: {MinWidth}x{MinHeight}")
  
  if width < OptimalWidth or height < OptimalHeight:
    return (true, &"Terminal smaller than optimal ({width}x{height}). Optimal: {OptimalWidth}x{OptimalHeight}. Using compact layout.")
  
  return (true, &"Terminal size OK ({width}x{height})")

proc shouldLaunchInNewWindow*(): bool =
  ## Determine if we should try to launch in a new window
  ## Returns false if we're already in an interactive terminal session
  
  # First check: Are we already in a TTY?
  # If stdin is a TTY, we're likely already in a terminal - don't spawn another
  when not defined(windows):
    if isatty(0) != 0:  # stdin (fd 0) is a TTY
      return false
  
  # If DISPLAY is set (X11) and we have a terminal emulator, launch new window
  when not defined(windows):
    if getEnv("DISPLAY") != "" or getEnv("WAYLAND_DISPLAY") != "":
      return true
  
  # If on macOS with GUI session (and not already in TTY per above check)
  when defined(macosx):
    return true
  
  # Otherwise run in current terminal
  return false
