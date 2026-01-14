## Event types for terminal input (keyboard, resize, errors).
##
## Provides unified event handling for all terminal interactions.

import std/[unicode, strutils]

type
  Key* {.pure.} = enum
    ## Virtual key codes for special keys and control sequences.
    None
    Rune          # Regular character - check `rune` field of KeyEvent
    
    # Common keys
    Enter, Tab, Backspace, Escape, Space
    
    # Arrow keys
    Up, Down, Left, Right
    
    # Navigation
    Home, End, PageUp, PageDown
    Insert, Delete
    
    # Function keys
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12
    F13, F14, F15, F16, F17, F18, F19, F20
    
    # Control keys (Ctrl+Letter)
    CtrlA, CtrlB, CtrlC, CtrlD, CtrlE, CtrlF, CtrlG
    CtrlH, CtrlI, CtrlJ, CtrlK, CtrlL, CtrlM, CtrlN
    CtrlO, CtrlP, CtrlQ, CtrlR, CtrlS, CtrlT, CtrlU
    CtrlV, CtrlW, CtrlX, CtrlY, CtrlZ

  ModMask* = distinct uint8
    ## Bitmask for modifier keys.

  KeyEvent* = object
    ## A keyboard event.
    key*: Key           # Virtual key code
    rune*: Rune         # Character rune (valid when key == Key.Rune)
    modifiers*: ModMask # Modifier keys pressed

  EventKind* {.pure.} = enum
    ## Type of terminal event.
    Key      # Keyboard input
    Resize   # Terminal window size changed
    Error    # Error occurred

  Event* = object
    ## Unified event type for all terminal events.
    case kind*: EventKind
    of EventKind.Key:
      keyEvent*: KeyEvent
    of EventKind.Resize:
      width*, height*: int
    of EventKind.Error:
      message*: string


# Modifier constants
const
  ModNone* = ModMask(0)
  ModShift* = ModMask(1 shl 0)
  ModCtrl* = ModMask(1 shl 1)
  ModAlt* = ModMask(1 shl 2)
  ModMeta* = ModMask(1 shl 3)

proc `and`*(a, b: ModMask): ModMask {.inline.} =
  ModMask(uint8(a) and uint8(b))

proc `or`*(a, b: ModMask): ModMask {.inline.} =
  ModMask(uint8(a) or uint8(b))

proc `==`*(a, b: ModMask): bool {.inline.} =
  uint8(a) == uint8(b)

proc `!=`*(a, b: ModMask): bool {.inline.} =
  uint8(a) != uint8(b)


# Event constructors
proc newKeyEvent*(key: Key, rune: Rune = Rune(0), mods: ModMask = ModNone): Event =
  ## Create a keyboard event.
  Event(
    kind: EventKind.Key,
    keyEvent: KeyEvent(key: key, rune: rune, modifiers: mods)
  )

proc newResizeEvent*(width, height: int): Event =
  ## Create a resize event.
  Event(
    kind: EventKind.Resize,
    width: width,
    height: height
  )

proc newErrorEvent*(message: string): Event =
  ## Create an error event.
  Event(
    kind: EventKind.Error,
    message: message
  )


# Key name mapping for debugging/display
proc name*(key: Key): string =
  ## Return printable name for a key.
  case key
  of Key.None: "None"
  of Key.Rune: "Rune"
  of Key.Enter: "Enter"
  of Key.Tab: "Tab"
  of Key.Backspace: "Backspace"
  of Key.Escape: "Escape"
  of Key.Space: "Space"
  of Key.Up: "Up"
  of Key.Down: "Down"
  of Key.Left: "Left"
  of Key.Right: "Right"
  of Key.Home: "Home"
  of Key.End: "End"
  of Key.PageUp: "PageUp"
  of Key.PageDown: "PageDown"
  of Key.Insert: "Insert"
  of Key.Delete: "Delete"
  of Key.F1: "F1"
  of Key.F2: "F2"
  of Key.F3: "F3"
  of Key.F4: "F4"
  of Key.F5: "F5"
  of Key.F6: "F6"
  of Key.F7: "F7"
  of Key.F8: "F8"
  of Key.F9: "F9"
  of Key.F10: "F10"
  of Key.F11: "F11"
  of Key.F12: "F12"
  of Key.F13: "F13"
  of Key.F14: "F14"
  of Key.F15: "F15"
  of Key.F16: "F16"
  of Key.F17: "F17"
  of Key.F18: "F18"
  of Key.F19: "F19"
  of Key.F20: "F20"
  of Key.CtrlA: "Ctrl-A"
  of Key.CtrlB: "Ctrl-B"
  of Key.CtrlC: "Ctrl-C"
  of Key.CtrlD: "Ctrl-D"
  of Key.CtrlE: "Ctrl-E"
  of Key.CtrlF: "Ctrl-F"
  of Key.CtrlG: "Ctrl-G"
  of Key.CtrlH: "Ctrl-H"
  of Key.CtrlI: "Ctrl-I"
  of Key.CtrlJ: "Ctrl-J"
  of Key.CtrlK: "Ctrl-K"
  of Key.CtrlL: "Ctrl-L"
  of Key.CtrlM: "Ctrl-M"
  of Key.CtrlN: "Ctrl-N"
  of Key.CtrlO: "Ctrl-O"
  of Key.CtrlP: "Ctrl-P"
  of Key.CtrlQ: "Ctrl-Q"
  of Key.CtrlR: "Ctrl-R"
  of Key.CtrlS: "Ctrl-S"
  of Key.CtrlT: "Ctrl-T"
  of Key.CtrlU: "Ctrl-U"
  of Key.CtrlV: "Ctrl-V"
  of Key.CtrlW: "Ctrl-W"
  of Key.CtrlX: "Ctrl-X"
  of Key.CtrlY: "Ctrl-Y"
  of Key.CtrlZ: "Ctrl-Z"

proc `$`*(ke: KeyEvent): string =
  ## String representation of key event with modifiers.
  var parts: seq[string] = @[]
  
  if (ke.modifiers and ModShift) != ModNone:
    parts.add("Shift")
  if (ke.modifiers and ModCtrl) != ModNone:
    parts.add("Ctrl")
  if (ke.modifiers and ModAlt) != ModNone:
    parts.add("Alt")
  if (ke.modifiers and ModMeta) != ModNone:
    parts.add("Meta")
  
  if ke.key == Key.Rune:
    parts.add("'" & $ke.rune & "'")
  else:
    parts.add(ke.key.name())
  
  result = parts.join("+")

proc `$`*(ev: Event): string =
  ## String representation of event.
  case ev.kind
  of EventKind.Key:
    "KeyEvent(" & $ev.keyEvent & ")"
  of EventKind.Resize:
    "ResizeEvent(" & $ev.width & "x" & $ev.height & ")"
  of EventKind.Error:
    "ErrorEvent(" & ev.message & ")"
