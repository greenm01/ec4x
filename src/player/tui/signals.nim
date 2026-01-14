## Signal handling for terminal events.
##
## Provides SIGWINCH (window resize) handling using atomic flag.
## Safe for use with raw terminal mode.

import std/atomics
import std/posix

# SIGWINCH is not defined in Nim's posix module, define it here
when not declared(SIGWINCH):
  var SIGWINCH {.importc, header: "<signal.h>".}: cint

var resizeFlag: Atomic[bool]
var resizeHandlerInstalled = false

proc sigwinchHandler(sig: cint) {.noconv.} =
  ## SIGWINCH signal handler.
  ## Sets atomic flag to indicate resize occurred.
  ## Must be async-signal-safe (no allocations, no syscalls).
  resizeFlag.store(true, moRelease)

proc setupResizeHandler*() =
  ## Install SIGWINCH signal handler.
  ## Safe to call multiple times (only installs once).
  if resizeHandlerInstalled:
    return
  
  var sa: Sigaction
  sa.sa_handler = sigwinchHandler
  sa.sa_flags = SA_RESTART  # Restart interrupted syscalls
  
  if sigaction(SIGWINCH, sa) == 0:
    resizeHandlerInstalled = true

proc checkResize*(): bool =
  ## Check if a resize event occurred.
  ## Returns true and clears flag if resize happened.
  ## Thread-safe via atomic operations.
  resizeFlag.exchange(false, moAcquire)

proc clearResizeFlag*() =
  ## Clear the resize flag without checking.
  resizeFlag.store(false, moRelease)
