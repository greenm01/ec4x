## TUI input mapping
##
## Maps raw key events to SAM proposals.

import std/[options, unicode, strutils]

import ../sam/sam_pkg
import ../tui/events

proc mapKeyEvent*(event: KeyEvent, model: TuiModel): Option[Proposal] =
  ## Map raw key events to SAM actions

  # Map key to KeyCode
  var keyCode = KeyCode.KeyNone
  var modifier = KeyModifier.None
  
  # Detect modifiers using bitmask
  let hasCtrl = (event.modifiers and ModCtrl) != ModNone
  let hasShift = (event.modifiers and ModShift) != ModNone
  let hasAlt = (event.modifiers and ModAlt) != ModNone
  
  # Check for combinations first, then single modifiers
  if hasAlt:
    modifier = KeyModifier.Alt
  elif hasCtrl:
    modifier = KeyModifier.Ctrl
  elif hasShift:
    modifier = KeyModifier.Shift

  # Intel note edit mode captures text input directly.
  if model.ui.intelNoteEditActive:
    case event.key
    of Key.Rune:
      if event.rune.int == 0x0D or event.rune.int == 0x0A:
        return some(actionIntelNoteInsertNewline())
      if event.rune.int >= 0x20:
        return some(actionIntelNoteAppend($event.rune))
      return none(Proposal)
    of Key.Enter:
      return some(actionIntelNoteInsertNewline())
    of Key.CtrlJ:
      return some(actionIntelNoteInsertNewline())
    of Key.CtrlS:
      return some(actionIntelNoteSave())
    of Key.Up:
      return some(actionIntelNoteCursorUp())
    of Key.Down:
      return some(actionIntelNoteCursorDown())
    of Key.Left:
      return some(actionIntelNoteCursorLeft())
    of Key.Right:
      return some(actionIntelNoteCursorRight())
    of Key.Backspace:
      return some(actionIntelNoteBackspace())
    of Key.Escape:
      return some(actionIntelNoteCancel())
    of Key.Delete:
      return some(actionIntelNoteDelete())
    else:
      return none(Proposal)

  # Message compose mode captures text input directly.
  if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
    case event.key
    of Key.Rune:
      if event.rune.int >= 0x20:
        return some(actionMessageComposeAppend($event.rune))
      return none(Proposal)
    of Key.Backspace:
      return some(actionMessageComposeBackspace())
    of Key.Left:
      return some(actionMessageComposeCursorLeft())
    of Key.Right:
      return some(actionMessageComposeCursorRight())
    of Key.Enter:
      return some(actionMessageSend())
    of Key.CtrlJ:
      return some(actionMessageSend())
    of Key.Escape:
      return some(actionMessageComposeToggle())
    else:
      return none(Proposal)

  case event.key
  of Key.Rune:
    if event.rune.int == 0x0D or event.rune.int == 0x0A:
      # CR/LF maps to Enter key - handled via KeyCode mapping below
      keyCode = KeyCode.KeyEnter
    else:
      # Allow meta+key to pass through to global bindings
      if modifier != KeyModifier.Alt:
          if not model.ui.quitConfirmationActive:
            if model.ui.expertModeActive:
              if event.rune.int >= 0x20:
                return some(actionExpertInputAppend($event.rune))
              return none(Proposal)
          # Entry modal import mode: append characters to nsec buffer
          if model.ui.appPhase == AppPhase.Lobby and
              model.ui.entryModal.mode == EntryModalMode.ImportNsec:
            if event.rune.int >= 0x20:
              return some(actionEntryImportAppend($event.rune))
            return none(Proposal)
          # Entry modal invite code input: append characters
          # Auto-focus to InviteCode when typing valid invite characters from GameList
          if model.ui.appPhase == AppPhase.Lobby and
              model.ui.entryModal.mode == EntryModalMode.Normal:
            if model.ui.entryModal.focus == EntryModalFocus.InviteCode:
              if event.rune.int >= 0x20:
                return some(actionEntryInviteAppend($event.rune))
              return none(Proposal)
            elif model.ui.entryModal.focus == EntryModalFocus.GameList:
              # Auto-focus to invite code when typing valid invite characters
              let ch = ($event.rune).toLowerAscii()
              if ch.len > 0 and (ch[0] in 'a'..'z' or ch[0] in '0'..'9' or ch[0] == '-'):
                return some(actionEntryInviteAppend($event.rune))
              # Otherwise fall through to key bindings
          # Lobby input mode: append characters to pubkey/name
          if model.ui.appPhase == AppPhase.Lobby and
              model.ui.lobbyInputMode != LobbyInputMode.None:
            if event.rune.int >= 0x20:
              return some(actionLobbyInputAppend($event.rune))
            return none(Proposal)
      let ch = $event.rune
      case ch
      of "0":
        keyCode = KeyCode.Key0
      of "1":
        keyCode = KeyCode.Key1
      of "2":
        keyCode = KeyCode.Key2
      of "3":
        keyCode = KeyCode.Key3
      of "4":
        keyCode = KeyCode.Key4
      of "5":
        keyCode = KeyCode.Key5
      of "6":
        keyCode = KeyCode.Key6
      of "7":
        keyCode = KeyCode.Key7
      of "8":
        keyCode = KeyCode.Key8
      of "9":
        keyCode = KeyCode.Key9
      of "q", "Q":
        keyCode = KeyCode.KeyQ
      of "c", "C":
        keyCode = KeyCode.KeyC
      of "f", "F":
        keyCode = KeyCode.KeyF
      of "o", "O":
        keyCode = KeyCode.KeyO
      of "m", "M":
        keyCode = KeyCode.KeyM
      of "e", "E":
        keyCode = KeyCode.KeyE
      of "h", "H":
        keyCode = KeyCode.KeyH
      of "x", "X":
        keyCode = KeyCode.KeyX
      of "s", "S":
        keyCode = KeyCode.KeyS
      of "l", "L":
        keyCode = KeyCode.KeyL
      of "b", "B":
        keyCode = KeyCode.KeyB
      of "g", "G":
        keyCode = KeyCode.KeyG
      of "r", "R":
        keyCode = KeyCode.KeyR
      of "j", "J":
        keyCode = KeyCode.KeyJ
      of "d", "D":
        keyCode = KeyCode.KeyD
      of "p", "P":
        keyCode = KeyCode.KeyP
      of "v", "V":
        keyCode = KeyCode.KeyV
      of "n", "N":
        keyCode = KeyCode.KeyN
      of "w", "W":
        keyCode = KeyCode.KeyW
      of "i", "I":
        keyCode = KeyCode.KeyI
      of "k", "K":
        keyCode = KeyCode.KeyK
      of "t", "T":
        keyCode = KeyCode.KeyT
      of "a", "A":
        keyCode = KeyCode.KeyA
      of "y", "Y":
        keyCode = KeyCode.KeyY
      of "u", "U":
        keyCode = KeyCode.KeyU
      of "z", "Z":
        keyCode = KeyCode.KeyZ
      of "+":
        keyCode = KeyCode.KeyPlus
        modifier = KeyModifier.Shift
      of "-":
        keyCode = KeyCode.KeyMinus
        modifier = KeyModifier.None
      of "=":
        keyCode = KeyCode.KeyPlus
        modifier = KeyModifier.None
      of "_":
        keyCode = KeyCode.KeyMinus
        modifier = KeyModifier.Shift
      of ":":
        keyCode = KeyCode.KeyColon
      of "/":
        keyCode = KeyCode.KeySlash
      else:
        discard
  of Key.Up:
    keyCode = KeyCode.KeyUp
  of Key.Down:
    keyCode = KeyCode.KeyDown
  of Key.Left:
    keyCode = KeyCode.KeyLeft
  of Key.Right:
    keyCode = KeyCode.KeyRight
  of Key.Enter:
    keyCode = KeyCode.KeyEnter
  of Key.CtrlJ:
    # Some terminals send LF (Ctrl-J) for Enter
    keyCode = KeyCode.KeyEnter
  of Key.Escape:
    keyCode = KeyCode.KeyEscape
  of Key.Tab:
    if (event.modifiers and ModShift) != ModNone:
      keyCode = KeyCode.KeyShiftTab
    else:
      keyCode = KeyCode.KeyTab
  of Key.CtrlO:
    keyCode = KeyCode.KeyO
    modifier = KeyModifier.Ctrl
  of Key.CtrlP:
    keyCode = KeyCode.KeyP
    modifier = KeyModifier.Ctrl
  of Key.CtrlG:
    keyCode = KeyCode.KeyG
    modifier = KeyModifier.Ctrl
  of Key.CtrlY:
    keyCode = KeyCode.KeyY
    modifier = KeyModifier.Ctrl
  of Key.CtrlF:
    keyCode = KeyCode.KeyF
    modifier = KeyModifier.Ctrl
  of Key.CtrlT:
    keyCode = KeyCode.KeyT
    modifier = KeyModifier.Ctrl
  of Key.CtrlE:
    keyCode = KeyCode.KeyE
    modifier = KeyModifier.Ctrl
  of Key.CtrlI:
    keyCode = KeyCode.KeyI
    modifier = KeyModifier.Ctrl
  of Key.CtrlN:
    keyCode = KeyCode.KeyN
    modifier = KeyModifier.Ctrl
  of Key.CtrlS:
    keyCode = KeyCode.KeyS
    modifier = KeyModifier.Ctrl
  of Key.CtrlK:
    keyCode = KeyCode.KeyK
    modifier = KeyModifier.Ctrl
  of Key.CtrlX:
    keyCode = KeyCode.KeyX
    modifier = KeyModifier.Ctrl
  of Key.CtrlL:
    keyCode = KeyCode.KeyCtrlL
  of Key.CtrlSlash:
    keyCode = KeyCode.KeySlash
    modifier = KeyModifier.Ctrl
  of Key.F1:
    keyCode = KeyCode.KeyF1
  of Key.F2:
    keyCode = KeyCode.KeyF2
  of Key.F3:
    keyCode = KeyCode.KeyF3
  of Key.F4:
    keyCode = KeyCode.KeyF4
  of Key.F5:
    keyCode = KeyCode.KeyF5
  of Key.F6:
    keyCode = KeyCode.KeyF6
  of Key.F7:
    keyCode = KeyCode.KeyF7
  of Key.F8:
    keyCode = KeyCode.KeyF8
  of Key.F9:
    keyCode = KeyCode.KeyF9
  of Key.F10:
    keyCode = KeyCode.KeyF10
  of Key.F11:
    keyCode = KeyCode.KeyF11
  of Key.F12:
    keyCode = KeyCode.KeyF12
  of Key.Home:
    keyCode = KeyCode.KeyHome
  of Key.Backspace:
    keyCode = KeyCode.KeyBackspace
  of Key.Delete:
    keyCode = KeyCode.KeyDelete
  of Key.PageUp:
    keyCode = KeyCode.KeyPageUp
  of Key.PageDown:
    keyCode = KeyCode.KeyPageDown
  else:
    discard

  # Use SAM action mapper
  mapKeyToAction(keyCode, modifier, model)
