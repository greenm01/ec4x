## TUI input mapping
##
## Maps raw key events to SAM proposals.

import std/[options, unicode]

import ../sam/sam_pkg
import ../tui/events

proc mapKeyEvent*(event: KeyEvent, model: TuiModel): Option[Proposal] =
  ## Map raw key events to SAM actions

  # Map key to KeyCode
  var keyCode = KeyCode.KeyNone

  case event.key
  of Key.Rune:
    if not model.quitConfirmationActive:
      if model.expertModeActive:
        if event.rune.int >= 0x20:
          return some(actionExpertInputAppend($event.rune))
        return none(Proposal)
      # Entry modal import mode: append characters to nsec buffer
      if model.appPhase == AppPhase.Lobby and
          model.entryModal.mode == EntryModalMode.ImportNsec:
        if event.rune.int >= 0x20:
          return some(actionEntryImportAppend($event.rune))
        return none(Proposal)
      # Entry modal invite code input: append characters
      if model.appPhase == AppPhase.Lobby and
          model.entryModal.mode == EntryModalMode.Normal and
          model.entryModal.focus == EntryModalFocus.InviteCode:
        if event.rune.int >= 0x20:
          return some(actionEntryInviteAppend($event.rune))
        return none(Proposal)
      # Lobby input mode: append characters to pubkey/name
      if model.appPhase == AppPhase.Lobby and
          model.lobbyInputMode != LobbyInputMode.None:
        if event.rune.int >= 0x20:
          return some(actionLobbyInputAppend($event.rune))
        return none(Proposal)
    let ch = $event.rune
    case ch
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
    of "t", "T":
      keyCode = KeyCode.KeyT
    of "a", "A":
      keyCode = KeyCode.KeyA
    of "y", "Y":
      keyCode = KeyCode.KeyY
    of "u", "U":
      keyCode = KeyCode.KeyU
    of ":":
      keyCode = KeyCode.KeyColon
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
  of Key.Escape:
    keyCode = KeyCode.KeyEscape
  of Key.Tab:
    if (event.modifiers and ModShift) != ModNone:
      keyCode = KeyCode.KeyShiftTab
    else:
      keyCode = KeyCode.KeyTab
  of Key.CtrlL:
    keyCode = KeyCode.KeyCtrlL
  of Key.CtrlE:
    keyCode = KeyCode.KeyCtrlE
  of Key.CtrlQ:
    keyCode = KeyCode.KeyCtrlQ
  of Key.Home:
    keyCode = KeyCode.KeyHome
  of Key.Backspace:
    keyCode = KeyCode.KeyBackspace
  else:
    discard

  # Use SAM action mapper
  mapKeyToAction(keyCode, model)
