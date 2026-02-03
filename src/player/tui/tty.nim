## TTY (terminal) control for raw mode and window size.
##
## Provides low-level terminal operations: entering/exiting raw mode,
## reading bytes, and querying window dimensions.
##
## Uses STDIN_FILENO (fd 0) for input rather than opening /dev/tty,
## which ensures correct behavior in both real terminals and PTY
## environments (script, expect, tmux, etc.)

import std/[posix, os, strutils]
import posix/termios
import ../../common/logger

type
  Tty* = object
    ## Terminal device handle with saved state.
    fd: cint
    savedState: Termios
    started: bool
    ownsfd: bool  # True if we opened the fd (vs using stdin)

  TtyError* = object of CatchableError
    ## Errors related to TTY operations.


proc openTty*(): Tty =
  ## Initialize TTY using stdin for input.
  ## This works correctly in both real terminals and PTY environments.
  ## Raises TtyError if stdin is not a terminal.
  let fd = cint(STDIN_FILENO)
  
  if isatty(fd) == 0:
    raise newException(TtyError, "stdin is not a terminal")
  
  result.fd = fd
  result.started = false
  result.ownsfd = false  # stdin, don't close it
  logInfo("TTY", "Using stdin, fd=", $fd)

proc start*(tty: var Tty): bool =
  ## Enter raw mode and save current terminal state.
  ## Returns true on success, false on failure.
  ## 
  ## Raw mode disables:
  ## - Line buffering (characters available immediately)
  ## - Echo (typed characters not displayed)
  ## - Signal generation (Ctrl-C, Ctrl-Z don't send signals)
  ## - Special character processing (no Ctrl-S/Q flow control)
  if tty.started:
    return true
  
  # Save current terminal state
  if tcGetAttr(tty.fd, addr tty.savedState) != 0:
    return false
  
  var raw = tty.savedState
  
  # Input flags: disable special processing
  # IXON: disable XON/XOFF flow control
  # ICRNL: disable CR to NL translation
  # BRKINT: break doesn't send SIGINT
  # INPCK: disable input parity checking
  # ISTRIP: don't strip 8th bit
  raw.c_iflag = raw.c_iflag and not (IXON or ICRNL or BRKINT or INPCK or ISTRIP)
  
  # Output flags: disable output processing
  # OPOST: disable all output processing
  raw.c_oflag = raw.c_oflag and not OPOST
  
  # Control flags: set 8-bit characters
  raw.c_cflag = (raw.c_cflag and not CSIZE) or CS8
  
  # Local flags: disable canonical mode, echo, signals
  # ICANON: disable line buffering
  # ECHO: disable echo
  # ISIG: disable signal generation (Ctrl-C, Ctrl-Z)
  # IEXTEN: disable extended processing (Ctrl-V)
  raw.c_lflag = raw.c_lflag and not (ICANON or ECHO or ISIG or IEXTEN)
  
  # Control characters: read returns immediately
  # VMIN = 1: read returns after 1 character
  # VTIME = 0: no timeout
  raw.c_cc[VMIN] = 1.char
  raw.c_cc[VTIME] = 0.char
  
  # Apply settings (TCSAFLUSH flushes input before applying)
  if tcSetAttr(tty.fd, TCSAFLUSH, addr raw) != 0:
    return false
  
  tty.started = true
  logInfo("TTY", "Raw mode entered, fd=", $tty.fd)
  return true

proc stop*(tty: var Tty): bool =
  ## Restore terminal to original state.
  ## Returns true on success, false on failure.
  if not tty.started:
    return true
  
  tty.started = false
  
  if tcSetAttr(tty.fd, TCSAFLUSH, addr tty.savedState) != 0:
    return false
  
  return true

proc readByte*(tty: Tty): int =
  ## Read a single byte from the terminal (blocking).
  ## Returns the byte value (0-255) or -1 on error/EOF.
  var c: char
  let n = read(tty.fd, addr c, 1)
  if n == 1:
    return ord(c)
  else:
    return -1

proc readByteTimeout*(tty: Tty, timeoutMs: int): int =
  ## Read a single byte from the terminal with timeout.
  ## Returns the byte value (0-255), -1 on error/EOF, or -2 on timeout.
  var pfd: TPollfd
  pfd.fd = tty.fd
  pfd.events = POLLIN
  pfd.revents = 0
  
  let ret = posix.poll(addr pfd, 1, cint(timeoutMs))
  
  if ret < 0:
    logWarn("TTY", "poll error, errno=", $errno)
    return -1  # Error
  elif ret == 0:
    return -2  # Timeout
  else:
    # Check for error conditions in revents
    if (pfd.revents and POLLNVAL) != 0:
      logWarn("TTY", "POLLNVAL - fd ", $tty.fd, " is invalid for poll!")
      return -1
    if (pfd.revents and POLLERR) != 0:
      logWarn("TTY", "POLLERR on fd ", $tty.fd)
      return -1
    if (pfd.revents and POLLHUP) != 0:
      logWarn("TTY", "POLLHUP on fd ", $tty.fd)
      return -1
      
    # Data available, read it
    var c: char
    let n = read(tty.fd, addr c, 1)
    if n == 1:
      return ord(c)
    else:
      logWarn("TTY", "read() returned ", $n, " on fd ", $tty.fd)
      return -1

proc readBytes*(tty: Tty, buf: var openArray[byte], maxBytes: int): int =
  ## Read up to maxBytes from terminal into buffer.
  ## Returns number of bytes read, or -1 on error.
  ## Non-blocking after first byte (returns what's available).
  let n = read(tty.fd, addr buf[0], cint(min(maxBytes, buf.len)))
  if n < 0:
    return -1
  return int(n)

proc windowSize*(tty: Tty): tuple[w, h: int] =
  ## Get terminal window dimensions in character cells.
  ## Falls back to 80x24 if ioctl fails.
  ## Also checks COLUMNS/LINES environment variables.
  var ws: IOctl_WinSize
  
  if ioctl(tty.fd, TIOCGWINSZ, addr ws) == 0:
    result.w = int(ws.ws_col)
    result.h = int(ws.ws_row)
  else:
    result.w = 0
    result.h = 0
  
  # Check environment variables as fallback/override
  if result.w == 0:
    let cols = getEnv("COLUMNS")
    if cols.len > 0:
      try:
        result.w = parseInt(cols)
      except ValueError:
        discard
  
  if result.h == 0:
    let lines = getEnv("LINES")
    if lines.len > 0:
      try:
        result.h = parseInt(lines)
      except ValueError:
        discard
  
  # Final fallback to standard default
  if result.w <= 0:
    result.w = 80
  if result.h <= 0:
    result.h = 24

proc close*(tty: var Tty) =
  ## Close the terminal device and restore state.
  if tty.fd >= 0:
    if tty.started:
      discard tty.stop()
    # Only close if we own the fd (not stdin)
    if tty.ownsfd:
      discard close(tty.fd)
    tty.fd = -1

proc fd*(tty: Tty): cint {.inline.} =
  ## Get the underlying file descriptor.
  ## Useful for low-level operations.
  tty.fd
