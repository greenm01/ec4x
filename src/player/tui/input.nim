## Input parsing for keyboard events.
##
## Parses raw terminal input bytes into structured key events.
## Handles escape sequences for special keys (arrows, function keys, etc.)
## following xterm/VT100 conventions.

import std/unicode
import std/tables
import events
import tty

type
  InputState {.pure.} = enum
    ## Parser state machine states.
    Init    # Normal input
    Esc     # Saw esc byte (0x1b)
    Csi     # In csi sequence (esc [)
    Ss3     # In SS3 sequence (esc O)

  InputParser* = object
    ## State machine for parsing input byte stream into events.
    state: InputState
    buf: seq[byte]         # Accumulated escape sequence bytes
    utf8buf: string        # Accumulated UTF-8 bytes


# csi key mapping: (final byte, param) -> (Key, ModMask)
# Based on xterm conventions
const csiKeyMap = {
  # Simple cursor keys
  ('A', 0): (Key.Up, ModNone),
  ('B', 0): (Key.Down, ModNone),
  ('C', 0): (Key.Right, ModNone),
  ('D', 0): (Key.Left, ModNone),
  ('H', 0): (Key.Home, ModNone),
  ('F', 0): (Key.End, ModNone),
  ('Z', 0): (Key.Tab, ModShift),  # Shift-Tab = Backtab
  
  # Keys with ~ suffix
  ('~', 1): (Key.Home, ModNone),
  ('~', 2): (Key.Insert, ModNone),
  ('~', 3): (Key.Delete, ModNone),
  ('~', 4): (Key.End, ModNone),
  ('~', 5): (Key.PageUp, ModNone),
  ('~', 6): (Key.PageDown, ModNone),
  ('~', 7): (Key.Home, ModNone),
  ('~', 8): (Key.End, ModNone),
  
  # Function keys via ~
  ('~', 11): (Key.F1, ModNone),
  ('~', 12): (Key.F2, ModNone),
  ('~', 13): (Key.F3, ModNone),
  ('~', 14): (Key.F4, ModNone),
  ('~', 15): (Key.F5, ModNone),
  ('~', 17): (Key.F6, ModNone),
  ('~', 18): (Key.F7, ModNone),
  ('~', 19): (Key.F8, ModNone),
  ('~', 20): (Key.F9, ModNone),
  ('~', 21): (Key.F10, ModNone),
  ('~', 23): (Key.F11, ModNone),
  ('~', 24): (Key.F12, ModNone),
  ('~', 25): (Key.F13, ModNone),
  ('~', 26): (Key.F14, ModNone),
  ('~', 28): (Key.F15, ModNone),
  ('~', 29): (Key.F16, ModNone),
  ('~', 31): (Key.F17, ModNone),
  ('~', 32): (Key.F18, ModNone),
  ('~', 33): (Key.F19, ModNone),
  ('~', 34): (Key.F20, ModNone),
}.toTable

# SS3 key mapping: esc O <char>
const ss3KeyMap = {
  'A': Key.Up,
  'B': Key.Down,
  'C': Key.Right,
  'D': Key.Left,
  'H': Key.Home,
  'F': Key.End,
  'P': Key.F1,
  'Q': Key.F2,
  'R': Key.F3,
  'S': Key.F4,
}.toTable


proc initParser*(): InputParser =
  ## Create a new input parser in initial state.
  InputParser(
    state: InputState.Init,
    buf: @[],
    utf8buf: ""
  )

proc reset(p: var InputParser) =
  ## Reset parser to initial state, discarding any partial sequences.
  p.state = InputState.Init
  p.buf.setLen(0)
  p.utf8buf.setLen(0)

proc parseCSI(p: var InputParser): Event =
  ## Parse accumulated csi sequence (esc [ ...).
  ## Returns a key event or error event.
  
  if p.buf.len == 0:
    p.reset()
    return newKeyEvent(Key.Escape)
  
  let final = char(p.buf[^1])
  
  # Extract parameter (if present)
  var param = 0
  if p.buf.len >= 2:
    # Simple number parsing (only handles single param)
    for i in 0..<(p.buf.len - 1):
      let c = char(p.buf[i])
      if c >= '0' and c <= '9':
        param = param * 10 + (ord(c) - ord('0'))
      else:
        break  # Stop on non-digit (modifier chars, etc.)
  
  # Look up in table
  if csiKeyMap.hasKey((final, param)):
    let (key, mods) = csiKeyMap[(final, param)]
    p.reset()
    return newKeyEvent(key, Rune(0), mods)
  
  # Unknown sequence - return Escape
  p.reset()
  return newKeyEvent(Key.Escape)

proc parseSS3(p: var InputParser): Event =
  ## Parse accumulated SS3 sequence (esc O <char>).
  
  if p.buf.len != 1:
    p.reset()
    return newKeyEvent(Key.Escape)
  
  let c = char(p.buf[0])
  if ss3KeyMap.hasKey(c):
    let key = ss3KeyMap[c]
    p.reset()
    return newKeyEvent(key)
  
  # Unknown sequence
  p.reset()
  return newKeyEvent(Key.Escape)

proc parseControlChar(b: byte): Event =
  ## Parse control character (0x00-0x1F).
  case b
  of 0x00: newKeyEvent(Key.CtrlA)  # Actually Ctrl-Space, but uncommon
  of 0x01: newKeyEvent(Key.CtrlA)
  of 0x02: newKeyEvent(Key.CtrlB)
  of 0x03: newKeyEvent(Key.CtrlC)
  of 0x04: newKeyEvent(Key.CtrlD)
  of 0x05: newKeyEvent(Key.CtrlE)
  of 0x06: newKeyEvent(Key.CtrlF)
  of 0x07: newKeyEvent(Key.CtrlG)
  of 0x08: newKeyEvent(Key.Backspace)  # Ctrl-H
  of 0x09: newKeyEvent(Key.Tab)        # Ctrl-I
  of 0x0A: newKeyEvent(Key.CtrlJ)      # Newline
  of 0x0B: newKeyEvent(Key.CtrlK)
  of 0x0C: newKeyEvent(Key.CtrlL)
  of 0x0D: newKeyEvent(Key.Enter)      # Ctrl-M / Carriage Return
  of 0x0E: newKeyEvent(Key.CtrlN)
  of 0x0F: newKeyEvent(Key.CtrlO)
  of 0x10: newKeyEvent(Key.CtrlP)
  of 0x11: newKeyEvent(Key.CtrlQ)
  of 0x12: newKeyEvent(Key.CtrlR)
  of 0x13: newKeyEvent(Key.CtrlS)
  of 0x14: newKeyEvent(Key.CtrlT)
  of 0x15: newKeyEvent(Key.CtrlU)
  of 0x16: newKeyEvent(Key.CtrlV)
  of 0x17: newKeyEvent(Key.CtrlW)
  of 0x18: newKeyEvent(Key.CtrlX)
  of 0x19: newKeyEvent(Key.CtrlY)
  of 0x1A: newKeyEvent(Key.CtrlZ)
  of 0x1B: newKeyEvent(Key.Escape)
  else: newKeyEvent(Key.None)

proc feedByte*(p: var InputParser, b: byte): seq[Event] =
  ## Feed a single byte to the parser.
  ## Returns 0 or more events (may return empty if waiting for more input).
  result = @[]
  
  case p.state
  of InputState.Init:
    # Normal state - check what we got
    if b == 0x1B:  # esc
      p.state = InputState.Esc
      p.buf.setLen(0)
    elif b == 0x7F:  # DEL (often Backspace)
      result.add(newKeyEvent(Key.Backspace))
    elif b < 0x20:  # Control character
      result.add(parseControlChar(b))
    elif b >= 0x20 and b < 0x7F:  # Printable ASCII
      result.add(newKeyEvent(Key.Rune, Rune(b)))
    elif b >= 0x80:  # Start of UTF-8 sequence
      p.utf8buf.add(char(b))
      # Try to decode
      try:
        let r = p.utf8buf.runeAt(0)
        result.add(newKeyEvent(Key.Rune, r))
        p.utf8buf.setLen(0)
      except:
        # Incomplete UTF-8, wait for more bytes
        discard
  
  of InputState.Esc:
    # After esc - determine sequence type
    if b == ord('['):  # csi
      p.state = InputState.Csi
      p.buf.setLen(0)
    elif b == ord('O'):  # SS3
      p.state = InputState.Ss3
      p.buf.setLen(0)
    else:
      # Alt+key or lone esc followed by key
      # For simplicity, treat as Alt+key if printable
      if b >= 0x20 and b < 0x7F:
        result.add(newKeyEvent(Key.Rune, Rune(b), ModAlt))
      else:
        result.add(newKeyEvent(Key.Escape))
        # Re-process this byte
        result.add(p.feedByte(b))
      p.reset()
  
  of InputState.Csi:
    # Accumulating csi sequence
    p.buf.add(b)
    # Check if this is a final byte (0x40-0x7E)
    if b >= 0x40 and b <= 0x7E:
      result.add(p.parseCSI())
  
  of InputState.Ss3:
    # Accumulating SS3 sequence (expect exactly one more byte)
    p.buf.add(b)
    result.add(p.parseSS3())

proc readEvent*(tty: Tty, parser: var InputParser): Event =
  ## Read and parse a single event from the terminal (blocking).
  ## Blocks until a complete key sequence is received.
  
  while true:
    let b = tty.readByte()
    if b < 0:
      return newErrorEvent("Read error from terminal")
    
    let events = parser.feedByte(byte(b))
    if events.len > 0:
      # Return first event, discard others for simplicity
      # (in practice, feedByte rarely returns >1 event)
      return events[0]
