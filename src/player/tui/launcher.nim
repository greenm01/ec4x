## TUI Launcher - Launch TUI in properly-sized terminal window
##
## Detects available terminal emulators and launches the TUI binary
## in a new window with optimal dimensions (120x36).
##
## If no suitable terminal is found, runs in current terminal with
## a size check and warning.

import std/[os, osproc, strformat, strutils]

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

proc launchInNewWindow*(binaryPath: string, width: int = OptimalWidth,
                        height: int = OptimalHeight): bool =
  ## Launch the TUI binary in a new terminal window
  ## Returns true if successfully launched in new window, false if fallback needed
  
  let terminal = detectTerminal()
  
  case terminal
  of TerminalEmulator.Foot:
    let cmd = &"foot --window-size-chars={width}x{height} {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.Ghostty:
    let cmd = &"ghostty --window-width={width} --window-height={height} {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.WezTerm:
    # WezTerm uses a config override approach
    let cmd = &"wezterm start --position 0,0 -- {binaryPath}"
    # Note: WezTerm doesn't easily support CLI geometry, rely on user config
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.GnomeTerminal:
    let cmd = &"gnome-terminal --geometry={width}x{height} -- {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.Konsole:
    let cmd = &"konsole --geometry {width}x{height} -e {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.Xterm:
    let cmd = &"xterm -geometry {width}x{height} -e {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.Alacritty:
    let cmd = &"alacritty --option window.dimensions.columns={width} " &
              &"--option window.dimensions.lines={height} -e {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.Kitty:
    let cmd = &"kitty --override initial_window_width={width}c " &
              &"--override initial_window_height={height}c {binaryPath}"
    discard startProcess(cmd, options = {poUsePath, poParentStreams})
    return true
  
  of TerminalEmulator.TerminalApp:
    # macOS Terminal.app via AppleScript
    let script = &"""
tell application "Terminal"
  activate
  set newTab to do script "cd '{getCurrentDir()}' && '{binaryPath}'"
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
  ## Check if we're already in a terminal session or if launched from desktop
  
  # If DISPLAY is set (X11) and we have a terminal emulator, launch new window
  when not defined(windows):
    if getEnv("DISPLAY") != "" or getEnv("WAYLAND_DISPLAY") != "":
      return true
  
  # If on macOS with GUI session
  when defined(macosx):
    return true
  
  # Otherwise run in current terminal
  return false
