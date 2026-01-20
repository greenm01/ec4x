## Entry Modal - Launch screen for identity and game selection
##
## The entry modal is the first screen players see. It displays:
## - EC4X ASCII logo
## - Player identity (npub + type)
## - List of active games (YOUR GAMES)
## - Invite code input (JOIN GAME)
##
## Reference: docs/architecture/nostr-protocol.md

import std/[strutils, options]
import ../../../common/logger
import ./modal
import ./text/text_pkg
import ./text_input
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../../state/identity

export text_input

type
  # Game info type for displaying active games
  EntryActiveGameInfo* = object
    id*: string
    name*: string
    turn*: int
    houseName*: string

const
  ModalMaxWidth = 72
  ModalMinWidth = 50
  ModalMinHeight = 24  # Increased to ensure relay section is visible
  FooterHeight = 1
  
  # ASCII art logo using Unicode block characters
  Logo* = [
    "███████╗ ██████╗██╗  ██╗██╗  ██╗",
    "██╔════╝██╔════╝██║  ██║╚██╗██╔╝",
    "█████╗  ██║     ███████║ ╚███╔╝ ",
    "██╔══╝  ██║     ╚════██║ ██╔██╗ ",
    "███████╗╚██████╗     ██║██╔╝ ██╗",
    "╚══════╝ ╚═════╝     ╚═╝╚═╝  ╚═╝"
  ]
  
  LogoWidth = 34
  LogoHeight = 6

  Version* = "v0.1.0"

var relayRenderLogged = false

type
  EntryModalFocus* {.pure.} = enum
    ## Which section has focus in the entry modal
    GameList
    InviteCode
    AdminMenu
    RelayUrl

  EntryModalMode* {.pure.} = enum
    ## Current mode of the entry modal
    Normal       ## Default: navigate games, enter invite code
    ImportNsec   ## Importing nsec identity
    CreateGame   ## Creating a new game (admin)
    ManageGames  ## Managing existing games (admin)

  AdminMenuItem* {.pure.} = enum
    ## Admin menu options
    CreateGame
    ManageGames

  CreateGameField* {.pure.} = enum
    ## Fields in the create game form
    GameName
    PlayerCount
    ConfirmCreate

  EntryModalState* = object
    ## State for the entry modal
    identity*: Identity
    activeGames*: seq[EntryActiveGameInfo]
    focus*: EntryModalFocus
    selectedIdx*: int
    mode*: EntryModalMode
    # Text input states (bounded display with scrolling)
    inviteInput*: TextInputState   ## Invite code input
    importInput*: TextInputState   ## nsec import input (masked)
    relayInput*: TextInputState    ## Relay URL input
    createNameInput*: TextInputState ## Game name input (max 32 chars)
    # Error messages
    inviteError*: string           ## Error message for invite code
    importError*: string           ## Error message for import
    createError*: string           ## Error message for game creation
    # Other state
    isAdmin*: bool                 ## Whether user has Admin privileges
    adminSelectedIdx*: int         ## Selected item in Admin menu
    managedGamesCount*: int        ## Number of games this admin manages
    editingRelay*: bool            ## Whether relay URL is being edited
    # Game creation state
    createPlayerCount*: int        ## Number of players (2-8)
    createField*: CreateGameField  ## Currently selected field

proc newEntryModalState*(): EntryModalState =
  ## Create initial entry modal state
  result = EntryModalState(
    identity: ensureIdentity(),
    activeGames: @[],
    focus: EntryModalFocus.GameList,
    selectedIdx: 0,
    mode: EntryModalMode.Normal,
    inviteInput: initTextInputState(maxLength = 0, maxDisplayWidth = 30),
    importInput: initTextInputState(maxLength = 0, maxDisplayWidth = 50),
    relayInput: initTextInputState(maxLength = 0, maxDisplayWidth = 40),
    createNameInput: initTextInputState(maxLength = 32, maxDisplayWidth = 30),
    inviteError: "",
    importError: "",
    createError: "",
    isAdmin: false,
    adminSelectedIdx: 0,
    managedGamesCount: 0,
    editingRelay: false,
    createPlayerCount: 4,  # Default 4 players
    createField: CreateGameField.GameName
  )
  # Set default relay URL
  result.relayInput.setText("ws://localhost:8080")

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------

proc selectedGame*(state: EntryModalState): Option[EntryActiveGameInfo] =
  ## Get the currently selected active game, if any
  if state.focus == EntryModalFocus.GameList and
     state.selectedIdx < state.activeGames.len:
    some(state.activeGames[state.selectedIdx])
  else:
    none(EntryActiveGameInfo)

proc moveUp*(state: var EntryModalState) =
  ## Move selection up in current section or switch focus
  case state.focus
  of EntryModalFocus.GameList:
    if state.selectedIdx > 0:
      state.selectedIdx -= 1
  of EntryModalFocus.InviteCode:
    # Move up to game list
    state.focus = EntryModalFocus.GameList
    if state.activeGames.len > 0:
      state.selectedIdx = state.activeGames.len - 1
  of EntryModalFocus.AdminMenu:
    if state.adminSelectedIdx > 0:
      state.adminSelectedIdx -= 1
    else:
      # At top of admin menu, move to invite code
      state.focus = EntryModalFocus.InviteCode
  of EntryModalFocus.RelayUrl:
    # Move up from relay to admin (if admin) or invite code
    if state.isAdmin:
      state.focus = EntryModalFocus.AdminMenu
      state.adminSelectedIdx = ord(AdminMenuItem.high)
    else:
      state.focus = EntryModalFocus.InviteCode

proc moveDown*(state: var EntryModalState) =
  ## Move selection down in current section or switch focus
  case state.focus
  of EntryModalFocus.GameList:
    if state.activeGames.len > 0 and
       state.selectedIdx < state.activeGames.len - 1:
      state.selectedIdx += 1
    else:
      # At bottom of list, move to invite code
      state.focus = EntryModalFocus.InviteCode
  of EntryModalFocus.InviteCode:
    if state.isAdmin:
      # Move to admin menu
      state.focus = EntryModalFocus.AdminMenu
      state.adminSelectedIdx = 0
    else:
      # Move to relay URL
      state.focus = EntryModalFocus.RelayUrl
  of EntryModalFocus.AdminMenu:
    if state.adminSelectedIdx < ord(AdminMenuItem.high):
      state.adminSelectedIdx += 1
    else:
      # At bottom of admin menu, move to relay URL
      state.focus = EntryModalFocus.RelayUrl
  of EntryModalFocus.RelayUrl:
    # At relay, wrap to game list
    state.focus = EntryModalFocus.GameList
    state.selectedIdx = 0

proc focusInviteCode*(state: var EntryModalState) =
  ## Focus the invite code input
  state.focus = EntryModalFocus.InviteCode

proc focusGameList*(state: var EntryModalState) =
  ## Focus the game list
  state.focus = EntryModalFocus.GameList
  if state.activeGames.len > 0 and state.selectedIdx >= state.activeGames.len:
    state.selectedIdx = 0

proc focusAdminMenu*(state: var EntryModalState) =
  ## Focus the admin menu (only if admin)
  if state.isAdmin:
    state.focus = EntryModalFocus.AdminMenu
    state.adminSelectedIdx = 0

proc selectedAdminMenuItem*(state: EntryModalState): Option[AdminMenuItem] =
  ## Get the currently selected admin menu item
  if state.focus == EntryModalFocus.AdminMenu and state.isAdmin:
    some(AdminMenuItem(state.adminSelectedIdx))
  else:
    none(AdminMenuItem)

proc setAdmin*(state: var EntryModalState, isAdmin: bool,
               managedGamesCount: int = 0) =
  ## Set admin status and managed games count
  state.isAdmin = isAdmin
  state.managedGamesCount = managedGamesCount

# -----------------------------------------------------------------------------
# Relay URL
# -----------------------------------------------------------------------------

proc startEditingRelay*(state: var EntryModalState) =
  ## Start editing the relay URL
  state.focus = EntryModalFocus.RelayUrl
  state.editingRelay = true

proc stopEditingRelay*(state: var EntryModalState) =
  ## Stop editing the relay URL
  state.editingRelay = false

proc relayUrl*(state: EntryModalState): string =
  ## Get the relay URL value
  state.relayInput.value()

# -----------------------------------------------------------------------------
# Game Creation
# -----------------------------------------------------------------------------

proc startGameCreation*(state: var EntryModalState) =
  ## Enter game creation mode
  state.mode = EntryModalMode.CreateGame
  state.createNameInput.clear()
  state.createPlayerCount = 4
  state.createField = CreateGameField.GameName
  state.createError = ""

proc cancelGameCreation*(state: var EntryModalState) =
  ## Cancel game creation and return to normal mode
  state.mode = EntryModalMode.Normal
  state.createNameInput.clear()
  state.createError = ""

proc createGameName*(state: EntryModalState): string =
  ## Get the game name value
  state.createNameInput.value()

proc createFieldUp*(state: var EntryModalState) =
  ## Move to previous field in create game form
  case state.createField
  of CreateGameField.GameName:
    discard  # Already at top
  of CreateGameField.PlayerCount:
    state.createField = CreateGameField.GameName
  of CreateGameField.ConfirmCreate:
    state.createField = CreateGameField.PlayerCount

proc createFieldDown*(state: var EntryModalState) =
  ## Move to next field in create game form
  case state.createField
  of CreateGameField.GameName:
    state.createField = CreateGameField.PlayerCount
  of CreateGameField.PlayerCount:
    state.createField = CreateGameField.ConfirmCreate
  of CreateGameField.ConfirmCreate:
    discard  # Already at bottom

proc incrementPlayerCount*(state: var EntryModalState) =
  ## Increase player count (max 8)
  if state.createPlayerCount < 8:
    state.createPlayerCount += 1

proc decrementPlayerCount*(state: var EntryModalState) =
  ## Decrease player count (min 2)
  if state.createPlayerCount > 2:
    state.createPlayerCount -= 1

proc setCreateError*(state: var EntryModalState, msg: string) =
  ## Set an error message for game creation
  state.createError = msg

# -----------------------------------------------------------------------------
# Invite Code
# -----------------------------------------------------------------------------

proc inviteCode*(state: EntryModalState): string =
  ## Get the invite code value
  state.inviteInput.value()

proc clearInviteCode*(state: var EntryModalState) =
  ## Clear the invite code
  state.inviteInput.clear()
  state.inviteError = ""

proc setInviteError*(state: var EntryModalState, msg: string) =
  ## Set an error message for the invite code
  state.inviteError = msg

# -----------------------------------------------------------------------------
# Import Mode
# -----------------------------------------------------------------------------

proc startImport*(state: var EntryModalState) =
  ## Enter import mode
  state.mode = EntryModalMode.ImportNsec
  state.importInput.clear()
  state.importError = ""

proc cancelImport*(state: var EntryModalState) =
  ## Cancel import mode
  state.mode = EntryModalMode.Normal
  state.importInput.clear()
  state.importError = ""

proc importBuffer*(state: EntryModalState): string =
  ## Get the import buffer value
  state.importInput.value()

proc confirmImport*(state: var EntryModalState): bool =
  ## Attempt to import the nsec
  ## Returns true on success, false on failure (check importError)
  try:
    state.identity = importIdentity(state.importInput.value())
    state.mode = EntryModalMode.Normal
    state.importInput.clear()
    state.importError = ""
    true
  except ValueError as e:
    state.importError = e.msg
    false

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc renderLogo(buf: var CellBuffer, area: Rect) =
  ## Render the EC4X ASCII logo centered in the area
  let logoStyle = CellStyle(
    fg: color(Ansi256Color(75)),  # tokyoBlue
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  
  let startX = area.x + (area.width - LogoWidth) div 2
  var y = area.y
  
  for line in Logo:
    if y >= area.bottom:
      break
    discard buf.setString(startX, y, line, logoStyle)
    y += 1

proc renderIdentitySection(buf: var CellBuffer, area: Rect,
                           identity: Identity, importHint: bool) =
  ## Render the identity section
  let headerStyle = modalBgStyle()
  let npubStyle = CellStyle(
    fg: color(PositiveColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let typeStyle = modalDimStyle()
  let hotkeyStyle = CellStyle(
    fg: color(Ansi256Color(223)),
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  let dimStyle = modalDimStyle()
  
  # Section header
  let headerText = "IDENTITY "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  # Identity display
  if area.height > 1:
    let npub = identity.npubTruncated
    let typeLabel = identity.typeLabel
    discard buf.setString(area.x, area.y + 1, npub, npubStyle)
    discard buf.setString(area.x + npub.len + 1, area.y + 1,
                          typeLabel, typeStyle)
    
    # Import hint on the right
    if importHint:
      let hint = "[I] Import nsec"
      let hintX = area.right - hint.len
      discard buf.setString(hintX, area.y + 1, "[", dimStyle)
      discard buf.setString(hintX + 1, area.y + 1, "I", hotkeyStyle)
      discard buf.setString(hintX + 2, area.y + 1, "]", dimStyle)
      discard buf.setString(hintX + 3, area.y + 1, " Import nsec", typeStyle)

proc renderGameList(buf: var CellBuffer, area: Rect,
                    games: seq[EntryActiveGameInfo], selectedIdx: int,
                    hasFocus: bool) =
  ## Render the list of active games
  let headerStyle = modalBgStyle()
  let cursorStyle = CellStyle(
    fg: color(Ansi256Color(110)),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let nameStyle = modalBgStyle()
  let infoStyle = modalDimStyle()
  let emptyStyle = modalDimStyle()
  
  # Section header
  let headerText = "YOUR GAMES "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  if games.len == 0:
    if area.height > 1:
      discard buf.setString(area.x + 2, area.y + 1,
                            "No active games", emptyStyle)
    return
  
  var y = area.y + 1
  for i, game in games:
    if y >= area.bottom:
      break
    
    let isSelected = hasFocus and i == selectedIdx
    
    # Cursor
    let cursor = if isSelected: "►" else: " "
    discard buf.setString(area.x, y, cursor, cursorStyle)
    
    # Game name (truncate if needed)
    let maxNameLen = 24
    var name = game.name
    if name.len > maxNameLen:
      name = name[0..<maxNameLen-1] & "…"
    discard buf.setString(area.x + 2, y, name, nameStyle)
    
    # Turn info
    let turnStr = "T" & $game.turn
    discard buf.setString(area.x + 28, y, turnStr, infoStyle)
    
    # House name
    discard buf.setString(area.x + 34, y, game.houseName, infoStyle)
    
    y += 1

proc renderInviteCodeSection(buf: var CellBuffer, area: Rect,
                              inviteInput: TextInputState,
                              errorMsg: string, hasFocus: bool) =
  ## Render the invite code input section
  let headerStyle = modalBgStyle()
  let promptStyle = modalDimStyle()
  let inputStyle = CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let cursorStyle = CellStyle(
    fg: color(Ansi256Color(110)),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let errorStyle = CellStyle(
    fg: color(AlertColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  # Section header
  let headerText = "JOIN GAME "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  if area.height > 1:
    # Focus cursor
    let cursor = if hasFocus: "►" else: " "
    discard buf.setString(area.x, area.y + 1, cursor, cursorStyle)
    
    # Prompt
    let prompt = "Invite code: "
    discard buf.setString(area.x + 2, area.y + 1, prompt, promptStyle)
    
    # Use TextInputWidget for bounded display
    let inputX = area.x + 2 + prompt.len
    let inputWidth = area.width - 2 - prompt.len - 1
    let inputArea = rect(inputX, area.y + 1, inputWidth, 1)
    let widget = newTextInput()
      .style(inputStyle)
      .cursorStyle(inputStyle)
    widget.render(inviteInput, inputArea, buf, hasFocus)
  
  # Error message
  if errorMsg.len > 0 and area.height > 2:
    discard buf.setString(area.x + 2, area.y + 2, errorMsg, errorStyle)

proc renderFooter(buf: var CellBuffer, area: Rect, focus: EntryModalFocus,
                  isAdmin: bool) =
  ## Render the footer with hotkeys and version
  let dimStyle = modalDimStyle()
  let keyStyle = CellStyle(
    fg: color(Ansi256Color(223)),
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  let textStyle = modalBgStyle()
  
  var x = area.x
  
  # [↑/↓] Navigate
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "↑/↓", keyStyle)
  x += 3
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " Nav  ", textStyle)
  x += 6
  
  case focus
  of EntryModalFocus.GameList:
    # [Enter] Play
    discard buf.setString(x, area.y, "[", dimStyle)
    x += 1
    discard buf.setString(x, area.y, "Enter", keyStyle)
    x += 5
    discard buf.setString(x, area.y, "]", dimStyle)
    x += 1
    discard buf.setString(x, area.y, " Play  ", textStyle)
    x += 7
  of EntryModalFocus.InviteCode:
    # [Enter] Join
    discard buf.setString(x, area.y, "[", dimStyle)
    x += 1
    discard buf.setString(x, area.y, "Enter", keyStyle)
    x += 5
    discard buf.setString(x, area.y, "]", dimStyle)
    x += 1
    discard buf.setString(x, area.y, " Join  ", textStyle)
    x += 7
  of EntryModalFocus.AdminMenu:
    # [Enter] Select
    discard buf.setString(x, area.y, "[", dimStyle)
    x += 1
    discard buf.setString(x, area.y, "Enter", keyStyle)
    x += 5
    discard buf.setString(x, area.y, "]", dimStyle)
    x += 1
    discard buf.setString(x, area.y, " Select  ", textStyle)
    x += 9
  of EntryModalFocus.RelayUrl:
    # [Enter] Edit
    discard buf.setString(x, area.y, "[", dimStyle)
    x += 1
    discard buf.setString(x, area.y, "Enter", keyStyle)
    x += 5
    discard buf.setString(x, area.y, "]", dimStyle)
    x += 1
    discard buf.setString(x, area.y, " Edit  ", textStyle)
    x += 7
  
  # [I] Import
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "I", keyStyle)
  x += 1
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " Import  ", textStyle)
  x += 9
  
  # [Q] Quit
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "Q", keyStyle)
  x += 1
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " Quit", textStyle)
  
  # Version on the right
  let versionX = area.right - Version.len
  discard buf.setString(versionX, area.y, Version, dimStyle)

proc renderAdminSection(buf: var CellBuffer, area: Rect,
                        selectedIdx: int, managedGamesCount: int,
                        hasFocus: bool) =
  ## Render the Admin section (only shown if user has Admin privileges)
  let headerStyle = modalBgStyle()
  let cursorStyle = CellStyle(
    fg: color(Ansi256Color(110)),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let itemStyle = modalBgStyle()
  let selectedItemStyle = CellStyle(
    fg: color(PositiveColor),
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  let infoStyle = modalDimStyle()
  
  # Section header
  let headerText = "ADMIN "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  if area.height > 1:
    var y = area.y + 1
    
    # Create New Game
    let isCreateSelected = hasFocus and selectedIdx == ord(AdminMenuItem.CreateGame)
    let createCursor = if isCreateSelected: "►" else: " "
    let createStyle = if isCreateSelected: selectedItemStyle else: itemStyle
    discard buf.setString(area.x, y, createCursor, cursorStyle)
    discard buf.setString(area.x + 2, y, "Create New Game", createStyle)
    y += 1
    
    # Manage My Games
    if y < area.bottom:
      let isManageSelected = hasFocus and
                             selectedIdx == ord(AdminMenuItem.ManageGames)
      let manageCursor = if isManageSelected: "►" else: " "
      let manageStyle = if isManageSelected: selectedItemStyle else: itemStyle
      discard buf.setString(area.x, y, manageCursor, cursorStyle)
      discard buf.setString(area.x + 2, y, "Manage My Games", manageStyle)
      
      # Show count if > 0
      if managedGamesCount > 0:
        let countStr = "(" & $managedGamesCount & ")"
        discard buf.setString(area.x + 18, y, countStr, infoStyle)

proc renderRelaySection(buf: var CellBuffer, area: Rect,
                        relayInput: TextInputState, editing: bool,
                        hasFocus: bool) =
  ## Render the relay URL configuration section
  let headerStyle = modalBgStyle()
  let promptStyle = modalDimStyle()
  let inputStyle = CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let cursorStyle = CellStyle(
    fg: color(Ansi256Color(110)),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  # Section header
  let headerText = "RELAY "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  if area.height > 1:
    # Focus cursor
    let cursor = if hasFocus: "►" else: " "
    discard buf.setString(area.x, area.y + 1, cursor, cursorStyle)
    
    # Prompt
    let prompt = "URL:"
    discard buf.setString(area.x + 2, area.y + 1, prompt, promptStyle)
    
    # Use TextInputWidget for bounded display
    let inputX = area.x + 2 + prompt.len + 1
    let inputWidth = area.width - 2 - prompt.len - 1
    if not relayRenderLogged:
      relayRenderLogged = true
      logInfo("EntryModal", "Relay input layout: area=", $area.width,
              " input=", $inputWidth, " value=", relayInput.value())
    let inputArea = rect(inputX, area.y + 1, inputWidth, 1)
    let widget = newTextInput()
      .style(inputStyle)
      .cursorStyle(inputStyle)
    widget.render(relayInput, inputArea, buf, editing and hasFocus)

proc renderImportMode(buf: var CellBuffer, inner: Rect, modalArea: Rect,
                      importInput: TextInputState, importError: string) =
  ## Render the import nsec mode
  let promptStyle = modalBgStyle()
  let inputStyle = CellStyle(
    fg: color(PositiveColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let errorStyle = CellStyle(
    fg: color(AlertColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let footerStyle = modalBgStyle()
  
  # Logo
  let logoArea = rect(inner.x, inner.y + 1, inner.width, LogoHeight)
  renderLogo(buf, logoArea)
  
  # Import prompt
  let promptY = inner.y + LogoHeight + 3
  let prompt = "Enter nsec: "
  discard buf.setString(inner.x, promptY, prompt, promptStyle)
  
  # Use TextInputWidget with masking for nsec
  let inputX = inner.x + prompt.len
  let inputWidth = inner.width - prompt.len - 1
  let inputArea = rect(inputX, promptY, inputWidth, 1)
  let widget = newTextInput()
    .masked(true)
    .style(inputStyle)
    .cursorStyle(inputStyle)
  widget.render(importInput, inputArea, buf, true)  # Always focused in import
  
  # Error message
  if importError.len > 0:
    discard buf.setString(inner.x, promptY + 1, importError, errorStyle)
  
  # Footer
  let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
  discard buf.setString(footerArea.x, footerArea.y,
                        "[Enter] Confirm   [Esc] Cancel", footerStyle)

proc renderCreateGameMode(buf: var CellBuffer, inner: Rect, modalArea: Rect,
                          state: EntryModalState) =
  ## Render the create game mode
  let headerStyle = modalBgStyle()
  let promptStyle = modalDimStyle()
  let inputStyle = CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let selectedStyle = CellStyle(
    fg: color(PositiveColor),
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  let cursorStyle = CellStyle(
    fg: color(Ansi256Color(110)),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let errorStyle = CellStyle(
    fg: color(AlertColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let buttonStyle = modalBgStyle()
  let selectedButtonStyle = CellStyle(
    fg: color(Ansi256Color(0)),  # Black text
    bg: color(PositiveColor),    # Green background
    attrs: {StyleAttr.Bold}
  )
  let footerStyle = modalBgStyle()
  
  # Logo
  let logoArea = rect(inner.x, inner.y + 1, inner.width, LogoHeight)
  renderLogo(buf, logoArea)
  
  var y = inner.y + LogoHeight + 3
  
  # Title
  let title = "CREATE NEW GAME "
  let ruleLen = inner.width - title.len - 1
  let titleLine = title & repeat("─", ruleLen)
  discard buf.setString(inner.x, y, titleLine, headerStyle)
  y += 2
  
  # Game Name field
  let nameSelected = state.createField == CreateGameField.GameName
  let nameCursor = if nameSelected: "►" else: " "
  let nameStyle = if nameSelected: selectedStyle else: inputStyle
  discard buf.setString(inner.x, y, nameCursor, cursorStyle)
  discard buf.setString(inner.x + 2, y, "Game Name: ", promptStyle)
  
  # Use TextInputWidget for game name
  let nameInputX = inner.x + 13
  let nameInputWidth = inner.width - 14
  let nameInputArea = rect(nameInputX, y, nameInputWidth, 1)
  let nameWidget = newTextInput()
    .style(nameStyle)
    .cursorStyle(nameStyle)
  nameWidget.render(state.createNameInput, nameInputArea, buf, nameSelected)
  y += 2
  
  # Player Count field
  let countSelected = state.createField == CreateGameField.PlayerCount
  let countCursor = if countSelected: "►" else: " "
  let countStyle = if countSelected: selectedStyle else: inputStyle
  discard buf.setString(inner.x, y, countCursor, cursorStyle)
  discard buf.setString(inner.x + 2, y, "Players:   ", promptStyle)
  let countStr = "◄ " & $state.createPlayerCount & " ►"
  discard buf.setString(inner.x + 13, y, countStr, countStyle)
  discard buf.setString(inner.x + 22, y, "(2-8)", promptStyle)
  y += 2
  
  # Error message
  if state.createError.len > 0:
    discard buf.setString(inner.x + 2, y, state.createError, errorStyle)
    y += 2
  
  # Create button
  let btnSelected = state.createField == CreateGameField.ConfirmCreate
  let btnCursor = if btnSelected: "►" else: " "
  let btnStyle = if btnSelected: selectedButtonStyle else: buttonStyle
  discard buf.setString(inner.x, y, btnCursor, cursorStyle)
  discard buf.setString(inner.x + 2, y, "[ Create Game ]", btnStyle)
  
  # Footer
  let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
  discard buf.setString(footerArea.x, footerArea.y,
                        "[↑/↓] Navigate  [←/→] Adjust  [Enter] Select  [Esc] Cancel",
                        footerStyle)

proc calculateContentHeight(state: EntryModalState): int =
  ## Calculate the content height needed
  # 1 (space after title) + Logo + blank + identity section + blank +
  # games section + blank + invite code section + (admin section if admin) +
  # relay section
  let gamesHeight = max(2, state.activeGames.len + 1)
  let inviteHeight = 3  # header + input + error line
  let adminHeight = if state.isAdmin: 4 else: 0  # header + 2 items + blank
  let relayHeight = 2  # header + input
  1 + LogoHeight + 1 + 3 + 1 + gamesHeight + 1 + inviteHeight + adminHeight +
    relayHeight

proc render*(state: EntryModalState, viewport: Rect, buf: var CellBuffer) =
  ## Render the complete entry modal
  let modal = newModal()
    .title("E C 4 X")
    .maxWidth(ModalMaxWidth)
    .minWidth(ModalMinWidth)
    .minHeight(ModalMinHeight)
  
  let contentHeight = state.calculateContentHeight
  let modalArea = modal.calculateArea(viewport, contentHeight + FooterHeight)
  
  # Render modal frame with footer separator
  modal.renderWithSeparator(modalArea, buf, FooterHeight)
  
  # Get inner content area
  let inner = modal.inner(modalArea)
  
  if state.mode == EntryModalMode.ImportNsec:
    renderImportMode(buf, inner, modalArea,
                     state.importInput, state.importError)
  elif state.mode == EntryModalMode.CreateGame:
    renderCreateGameMode(buf, inner, modalArea, state)
  elif state.mode == EntryModalMode.ManageGames:
    # TODO: Implement manage games mode
    renderImportMode(buf, inner, modalArea,
                     state.importInput, "Manage Games: Not implemented")
  else:
    # Normal mode
    var y = inner.y + 1  # Space after title bar
    
    # Logo
    let logoArea = rect(inner.x, y, inner.width, LogoHeight)
    renderLogo(buf, logoArea)
    y += LogoHeight + 1
    
    # Identity section
    let identityArea = rect(inner.x, y, inner.width, 3)
    renderIdentitySection(buf, identityArea, state.identity, true)
    y += 3 + 1
    
    # Your Games section
    let gamesHeight = max(2, state.activeGames.len + 1)
    let gamesArea = rect(inner.x, y, inner.width, gamesHeight)
    renderGameList(buf, gamesArea, state.activeGames, state.selectedIdx,
                   state.focus == EntryModalFocus.GameList)
    y += gamesHeight + 1
    
    # Join Game section (invite code input)
    let inviteArea = rect(inner.x, y, inner.width, 3)
    renderInviteCodeSection(buf, inviteArea, state.inviteInput,
                            state.inviteError,
                            state.focus == EntryModalFocus.InviteCode)
    y += 3 + 1
    
    # Admin section (only if user has Admin privileges)
    if state.isAdmin:
      let adminArea = rect(inner.x, y, inner.width, 3)
      renderAdminSection(buf, adminArea, state.adminSelectedIdx,
                         state.managedGamesCount,
                         state.focus == EntryModalFocus.AdminMenu)
      y += 4
    
    # Relay section
    let relayArea = rect(inner.x, y, inner.width, 2)
    renderRelaySection(buf, relayArea, state.relayInput, state.editingRelay,
                       state.focus == EntryModalFocus.RelayUrl)
    
    # Footer
    let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
    renderFooter(buf, footerArea, state.focus, state.isAdmin)
