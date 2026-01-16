## Platform-specific terminal detection.
##
## Provides color profile detection based on environment variables
## and terminal capabilities. Uses compile-time platform detection.

import std/[os, strutils, terminal]
import types/core

# =============================================================================
# Environment Helpers
# =============================================================================

proc getEnvOrDefault(key: string, default: string = ""): string =
  getEnv(key, default)

proc hasEnv(key: string): bool =
  existsEnv(key)


# =============================================================================
# NO_COLOR / CLICOLOR Standards
# =============================================================================

proc envNoColor*(): bool =
  ## Check if NO_COLOR environment variable is set.
  ## https://no-color.org/
  hasEnv("NO_COLOR")

proc envForceColor*(): bool =
  ## Check if CLICOLOR_FORCE is set to enable color.
  let force = getEnvOrDefault("CLICOLOR_FORCE", "0")
  force != "0" and force != ""

proc envCliColor*(): bool =
  ## Check CLICOLOR setting.
  ## Returns true unless explicitly disabled.
  let clicolor = getEnvOrDefault("CLICOLOR", "1")
  clicolor != "0"


# =============================================================================
# Profile Detection
# =============================================================================

const TrueColorTerminals = [
  "alacritty",
  "contour",
  "foot",
  "ghostty",
  "kitty",
  "rio",
  "wezterm",
  "xterm-256color",   # Many true color terms use this
  "xterm-ghostty",
  "xterm-kitty"
]

const Ansi256Terminals = [
  "256color",
  "xterm-256color",
  "screen-256color",
  "tmux-256color"
]

proc detectProfile*(): Profile =
  ## Detect terminal color profile from environment.
  ## Checks various environment variables and terminal info.
  
  # NO_COLOR takes precedence
  if envNoColor():
    return Profile.Ascii

  # Check COLORTERM for true color
  let colorterm = getEnvOrDefault("COLORTERM").toLowerAscii
  if colorterm in ["truecolor", "24bit"]:
    return Profile.TrueColor

  # Check TERM for known terminals
  let term = getEnvOrDefault("TERM").toLowerAscii

  # Check for true color terminals
  for t in TrueColorTerminals:
    if t in term:
      return Profile.TrueColor

  # Check for 256-color support
  for t in Ansi256Terminals:
    if t in term:
      return Profile.Ansi256

  # Generic color checks
  if "color" in term or "ansi" in term:
    return Profile.Ansi

  # Check if we're in a known color-capable environment
  if hasEnv("GOOGLE_CLOUD_SHELL"):
    return Profile.TrueColor

  # Check WT_SESSION (Windows Terminal)
  if hasEnv("WT_SESSION"):
    return Profile.TrueColor

  # Check TERM_PROGRAM for macOS terminals
  let termProgram = getEnvOrDefault("TERM_PROGRAM")
  case termProgram.toLowerAscii
  of "apple_terminal":
    return Profile.Ansi256
  of "iterm.app":
    return Profile.TrueColor
  of "hyper":
    return Profile.TrueColor
  of "vscode":
    return Profile.TrueColor
  else:
    discard

  # Default based on CLICOLOR
  if envCliColor() or envForceColor():
    return Profile.Ansi

  # Fallback: check if stdout is a TTY
  if isatty(stdout):
    return Profile.Ansi

  Profile.Ascii

proc envColorProfile*(): Profile =
  ## Get color profile from environment.
  ## Alias for detectProfile.
  detectProfile()


# =============================================================================
# Terminal Capability Queries (Stubs)
# =============================================================================

proc queryForegroundColor*(): Color =
  ## Query terminal foreground color via osc 10.
  ## TODO: Implement terminal query protocol.
  noColor()

proc queryBackgroundColor*(): Color =
  ## Query terminal background color via osc 11.
  ## TODO: Implement terminal query protocol.
  noColor()

proc queryCursorPosition*(): tuple[row, col: int] =
  ## Query cursor position via DSR.
  ## TODO: Implement terminal query protocol.
  (0, 0)


# =============================================================================
# Platform-Specific (Unix)
# =============================================================================

when defined(posix):
  proc isForeground*(): bool =
    ## Check if process is in foreground.
    ## TODO: Implement using tcgetpgrp.
    true

  proc enableRawMode*(): bool =
    ## Enable raw terminal mode.
    ## TODO: Implement using termios.
    false

  proc disableRawMode*(): bool =
    ## Disable raw terminal mode.
    ## TODO: Implement using termios.
    false


# =============================================================================
# Platform-Specific (Windows)
# =============================================================================

when defined(windows):
  proc enableVirtualTerminalProcessing*(): bool =
    ## Enable VT processing on Windows console.
    ## TODO: Implement using SetConsoleMode.
    false

  proc disableVirtualTerminalProcessing*(): bool =
    ## Disable VT processing on Windows console.
    ## TODO: Implement using SetConsoleMode.
    false

  proc isForeground*(): bool =
    ## Check if process is in foreground.
    true
