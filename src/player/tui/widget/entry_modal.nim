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
import ./scrollbar
import ./table
import ../buffer
import ../layout/rect
import ../styles/ec_palette
import ../../state/identity
import ../../state/wallet

export text_input

type
  # Game info type for displaying active games
  EntryActiveGameInfo* = object
    id*: string
    name*: string
    turn*: int
    houseName*: string
    houseId*: int
    status*: string

const
  ModalMaxWidth = 84
  ModalMinWidth = 84
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
    PasswordPrompt ## Prompting for password to unlock wallet

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
    wallet*: IdentityWallet
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
    passwordInput*: TextInputState ## Wallet password input
    importMasked*: bool            ## Toggle for masking sensitive inputs
    # Error messages
    inviteError*: string           ## Error message for invite code
    importError*: string           ## Error message for import
    createError*: string           ## Error message for game creation
    # Other state
    isAdmin*: bool                 ## Whether user has Admin privileges
    adminSelectedIdx*: int         ## Selected item in Admin menu
    managedGamesCount*: int        ## Number of games this admin manages
    editingRelay*: bool            ## Whether relay URL is being edited
    nostrStatus*: string           ## Nostr connection status
    # Game creation state
    createPlayerCount*: int        ## Number of players (2-8)
    createField*: CreateGameField  ## Currently selected field

proc newEntryModalState*(): EntryModalState =
  ## Create initial entry modal state
  let walletResult = ensureWallet()
  
  var activeWallet = IdentityWallet(identities: @[], activeIdx: 0)
  var activeIdentity = Identity()
  var initialMode = EntryModalMode.Normal
  
  if walletResult.status == WalletLoadStatus.Success:
    activeWallet = walletResult.wallet.get()
    activeIdentity = activeWallet.activeIdentity()
  elif walletResult.status == WalletLoadStatus.NeedsPassword or walletResult.status == WalletLoadStatus.WrongPassword:
    initialMode = EntryModalMode.PasswordPrompt

  result = EntryModalState(
    wallet: activeWallet,
    identity: activeIdentity,
    activeGames: @[],
    focus: EntryModalFocus.GameList,
    selectedIdx: 0,
    mode: initialMode,
    inviteInput: initTextInputState(maxLength = 0, maxDisplayWidth = 30),
    importInput: initTextInputState(maxLength = 0, maxDisplayWidth = 50),
    relayInput: initTextInputState(maxLength = 0, maxDisplayWidth = 40),
    createNameInput: initTextInputState(maxLength = 32, maxDisplayWidth = 30),
    passwordInput: initTextInputState(maxLength = 0, maxDisplayWidth = 30),
    importMasked: true,
    inviteError: "",
    importError: "",
    createError: "",
    isAdmin: false,
    adminSelectedIdx: 0,
    managedGamesCount: 0,
    editingRelay: false,
    nostrStatus: "idle",
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

proc toggleMask*(state: var EntryModalState) =
  ## Toggle the masked state for sensitive inputs
  state.importMasked = not state.importMasked

proc cancelImport*(state: var EntryModalState) =
  ## Cancel import mode
  state.mode = EntryModalMode.Normal
  state.importInput.clear()
  state.importError = ""

proc importBuffer*(state: EntryModalState): string =
  ## Get the import buffer value
  state.importInput.value()

proc unlockWallet*(state: var EntryModalState): bool =
  ## Attempt to unlock the wallet
  let password = state.passwordInput.value()
  let result = ensureWallet(some(password))
  if result.status == WalletLoadStatus.Success:
    state.wallet = result.wallet.get()
    state.identity = state.wallet.activeIdentity()
    state.mode = EntryModalMode.Normal
    state.passwordInput.clear()
    state.importError = ""
    return true
  else:
    state.importError = "Incorrect password or corrupted wallet."
    return false

proc confirmImport*(state: var EntryModalState): bool =
  ## Attempt to import the nsec
  ## Returns true on success, false on failure (check importError)
  try:
    state.identity = state.wallet.importIntoWallet(state.importInput.value())
    state.mode = EntryModalMode.Normal
    state.importInput.clear()
    state.importError = ""
    true
  except ValueError as e:
    state.importError = e.msg
    false

proc selectNextIdentity*(state: var EntryModalState): bool =
  ## Activate the next identity in the wallet.
  if state.wallet.cycleActive(1):
    state.identity = state.wallet.activeIdentity()
    return true
  false

proc selectPrevIdentity*(state: var EntryModalState): bool =
  ## Activate the previous identity in the wallet.
  if state.wallet.cycleActive(-1):
    state.identity = state.wallet.activeIdentity()
    return true
  false

proc createIdentity*(state: var EntryModalState) =
  ## Create and activate a new local identity.
  state.identity = state.wallet.createNewLocalIdentity()

proc identityCount*(state: EntryModalState): int =
  state.wallet.identities.len

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc renderLogo(buf: var CellBuffer, area: Rect) =
  ## Render the EC4X ASCII logo centered in the area
  let logoStyle = CellStyle(
    fg: color(CursorColor),
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
                           identity: Identity, identityIndex: int,
                           identityCount: int, importHint: bool) =
  ## Render the active identity information
  let headerStyle = modalBgStyle()
  let npubStyle = CellStyle(
    fg: color(NeutralColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let typeStyle = CellStyle(
    fg: color(NeutralColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  # Section header
  let headerText = "IDENTITY "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  
  # Identity display
  if area.height > 1:
    let npub = identity.npubTruncated
    let typeLabel = identity.typeLabel
    let countLabel = " [" & $(identityIndex + 1) & "/" &
      $identityCount & "]"
    discard buf.setString(area.x, area.y + 1, npub, npubStyle)
    discard buf.setString(area.x + npub.len + 1, area.y + 1,
                          typeLabel, typeStyle)
    discard buf.setString(area.x + npub.len + typeLabel.len + 2,
      area.y + 1, countLabel, typeStyle)

    if importHint and area.height > 2:
      # Removed redundant hints from under IDENTITY to save vertical space.
      discard

proc renderGameList(buf: var CellBuffer, area: Rect,
                    games: seq[EntryActiveGameInfo], selectedIdx: int,
                    hasFocus: bool) =
  ## Render the list of active games
  let headerStyle = modalBgStyle()
  let emptyStyle = modalDimStyle()
  
  # Section header
  let headerText = "YOUR GAMES "
  let ruleLen = area.width - headerText.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  discard buf.setString(area.x, area.y, headerLine, headerStyle)

  let listHeight = area.height - 1
  if listHeight <= 0:
    return
  
  var activeGames: seq[EntryActiveGameInfo] = @[]
  var archivedGames: seq[EntryActiveGameInfo] = @[]
  for game in games:
    if game.houseId <= 0:
      continue
    if game.status == "completed":
      archivedGames.add(game)
    else:
      activeGames.add(game)
  if activeGames.len == 0 and archivedGames.len == 0:
    if area.height > 1:
      discard buf.setString(area.x + 2, area.y + 1,
                            "None", emptyStyle)
    return
  
  var y = area.y + 1
  var renderedActive = 0
  if activeGames.len == 0:
    discard buf.setString(area.x + 2, y, "None", emptyStyle)
    renderedActive = 1
    y += 1
  else:
    var boundedSelected = selectedIdx
    if boundedSelected < 0:
      boundedSelected = 0
    if boundedSelected >= activeGames.len:
      boundedSelected = activeGames.len - 1
    let maxStart = max(0, activeGames.len - listHeight)
    var startIdx = 0
    if activeGames.len > listHeight:
      startIdx = boundedSelected - listHeight + 1
      if startIdx < 0:
        startIdx = 0
      if startIdx > maxStart:
        startIdx = maxStart

    let selIdx = if hasFocus: boundedSelected else: -1
    var gameTable = table([
      tableColumn("Name", width = 24),
      tableColumn("Turn", width = 6),
      tableColumn("House", width = 0, minWidth = 4)
    ]).showBorders(false)
      .showHeader(false)
      .showSeparator(false)
      .cellPadding(1)
      .rowStyle(modalBgStyle())
      .selectedStyle(selectedStyle())
      .selectedIdx(selIdx)
      .scrollOffset(startIdx)
    for game in activeGames:
      var name = game.name
      if name.len > 24:
        name = name[0..<23] & "\xe2\x80\xa6"
      let turnStr = "T" & $game.turn
      gameTable.addRow(@[name, turnStr, game.houseName])

    let tableArea = rect(area.x, y,
                         area.width, listHeight)
    gameTable.render(tableArea, buf)

    let endIdx = min(activeGames.len, startIdx + listHeight)
    renderedActive = endIdx - startIdx
    y = area.y + 1 + renderedActive

    if activeGames.len > listHeight and listHeight > 1:
      let listArea = rect(area.x, area.y + 1,
                          area.width, listHeight)
      let scrollbarState = ScrollbarState(
        contentLength: activeGames.len,
        position: startIdx,
        viewportLength: listHeight
      )
      renderScrollbar(listArea, buf, scrollbarState,
        ScrollbarOrientation.VerticalRight)

  if archivedGames.len > 0 and y < area.bottom:
    let archivedHeader = "ARCHIVED "
    let archivedRule = area.width - archivedHeader.len - 1
    let archivedLine = archivedHeader & repeat("─", archivedRule)
    discard buf.setString(area.x, y, archivedLine, headerStyle)
    y += 1

    let archHeight = min(archivedGames.len, area.bottom - y)
    if archHeight > 0:
      var archTable = table([
        tableColumn("Name", width = 24),
        tableColumn("Turn", width = 6),
        tableColumn("House", width = 0, minWidth = 4)
      ]).showBorders(false)
        .showHeader(false)
        .showSeparator(false)
        .cellPadding(1)
        .rowStyle(modalDimStyle())
      for game in archivedGames:
        archTable.addRow(@[game.name,
                           "T" & $game.turn,
                           game.houseName])
      let archArea = rect(area.x, y,
                          area.width, archHeight)
      archTable.render(archArea, buf)
      y += archHeight

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
    fg: color(CursorColor),
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
    fg: color(KeyHintColor),
    bg: color(TrueBlackColor),
    attrs: {StyleAttr.Bold}
  )
  let textStyle = modalBgStyle()
  
  var x = area.x
  
  # [Up/Dn] Navigate
  let width1 = buf.setString(x, area.y, "[", dimStyle)
  x += width1
  let width2 = buf.setString(x, area.y, "↑↓", keyStyle)
  x += width2
  let width3 = buf.setString(x, area.y, "]", dimStyle)
  x += width3
  let width4 = buf.setString(x, area.y, " Nav  ", textStyle)
  x += width4
  
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
  
  # [Ctrl-I] Import
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "Ctrl-I", keyStyle)
  x += 6
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " Import  ", textStyle)
  x += 9

  # [Ctrl-T] Cycle ID
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "Ctrl-T", keyStyle)
  x += 6
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " ID  ", textStyle)
  x += 5

  # [Ctrl-N] New key
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "Ctrl-N", keyStyle)
  x += 6
  discard buf.setString(x, area.y, "]", dimStyle)
  x += 1
  discard buf.setString(x, area.y, " New  ", textStyle)
  x += 6
  
  # [F12] Quit
  discard buf.setString(x, area.y, "[", dimStyle)
  x += 1
  discard buf.setString(x, area.y, "F12", keyStyle)
  x += 3
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
    fg: color(CursorColor),
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
                        hasFocus: bool, nostrStatus: string) =
  ## Render the relay URL configuration section
  let headerStyle = modalBgStyle()
  let promptStyle = modalDimStyle()
  let inputStyle = CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  let cursorStyle = CellStyle(
    fg: color(CursorColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  # Connection status indicator and color (using ASCII text for visibility)
  let (statusText, statusColor) = case nostrStatus
    of "connected": ("[OK]", color(PositiveColor))
    of "connecting": ("[...]", color(WarningColor))
    of "error": ("[ERR]", color(AlertColor))
    else: ("[--]", color(DisabledColor))  # idle/unknown
  
  let statusStyle = CellStyle(
    fg: statusColor,
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  # Section header with status
  # Render: "RELAY ────────────────────────────────────────────── [OK]"
  let headerText = "RELAY "
  let statusSuffix = " " & statusText
  let ruleLen = area.width - headerText.len - statusSuffix.len - 1
  let headerLine = headerText & repeat("─", ruleLen)
  # Render header (RELAY + dashes) in default style
  discard buf.setString(area.x, area.y, headerLine, headerStyle)
  # Render status suffix in colored style at visual position (not byte position)
  let statusX = area.x + headerText.len + ruleLen
  discard buf.setString(statusX, area.y, statusSuffix, statusStyle)
  
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

proc renderPasswordPromptMode(buf: var CellBuffer, inner: Rect, modalArea: Rect,
                              passwordInput: TextInputState, importError: string,
                              isMasked: bool) =
  ## Render the password prompt mode
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
  let footerStyle = CellStyle(
    fg: color(NeutralColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )
  
  let logoArea = rect(inner.x, inner.y + 1, inner.width, LogoHeight)
  renderLogo(buf, logoArea)
  
  let promptY = inner.y + LogoHeight + 3
  let prompt = "Enter wallet password: "
  discard buf.setString(inner.x, promptY, prompt, promptStyle)
  
  let inputX = inner.x + prompt.len
  let inputWidth = inner.width - prompt.len - 1
  let inputArea = rect(inputX, promptY, inputWidth, 1)
  let widget = newTextInput()
    .masked(isMasked)
    .style(inputStyle)
    .cursorStyle(inputStyle)
  widget.render(passwordInput, inputArea, buf, true)  # Always focused
  
  if importError.len > 0:
    discard buf.setString(inner.x, promptY + 1, importError, errorStyle)
  
  let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
  discard buf.setString(footerArea.x, footerArea.y,
                        "[Tab] Show/Hide   [Enter] Unlock   [Esc] Quit", footerStyle)

proc renderImportMode(buf: var CellBuffer, inner: Rect, modalArea: Rect,
                      importInput: TextInputState, importError: string,
                      isMasked: bool) =
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
  let prompt = "Enter nsec or hex: "
  discard buf.setString(inner.x, promptY, prompt, promptStyle)
  
  # Use TextInputWidget with masking for nsec
  let inputX = inner.x + prompt.len
  let inputWidth = inner.width - prompt.len - 1
  let inputArea = rect(inputX, promptY, inputWidth, 1)
  let widget = newTextInput()
    .masked(isMasked)
    .style(inputStyle)
    .cursorStyle(inputStyle)
  widget.render(importInput, inputArea, buf, true)  # Always focused in import
  
  # Error message
  if importError.len > 0:
    discard buf.setString(inner.x, promptY + 1, importError, errorStyle)
  
  # Footer
  let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
  discard buf.setString(footerArea.x, footerArea.y,
                        "[Tab] Show/Hide   [Enter] Confirm   [Esc] Cancel", footerStyle)

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
    fg: color(CursorColor),
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
    fg: color(SelectedFgColor),
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
  let footerHint = "[↑↓] Navigate  [←→] Adjust  [Enter] Select  [Esc] Cancel"
  discard buf.setString(footerArea.x, footerArea.y, footerHint, footerStyle)

proc desiredGamesHeight(state: EntryModalState): int =
  ## Calculate the games section height with all rows
  var activeCount = 0
  var archivedCount = 0
  for game in state.activeGames:
    if game.houseId <= 0:
      continue
    if game.status == "completed":
      archivedCount += 1
    else:
      activeCount += 1
  let activeRows = if activeCount > 0: activeCount else: 1
  let archivedRows = if archivedCount > 0: archivedCount + 1 else: 0
  1 + activeRows + archivedRows

proc calculateContentHeight(state: EntryModalState, gamesHeight: int): int =
  ## Calculate content height with a specific games section size
  let inviteHeight = 3  # header + input + error line
  let adminHeight = if state.isAdmin: 4 else: 0  # header + 2 items + blank
  let relayHeight = 2  # header + input
  1 + LogoHeight + 1 + 2 + 1 + gamesHeight + 1 + inviteHeight + adminHeight +
    relayHeight

proc render*(state: EntryModalState, viewport: Rect, buf: var CellBuffer) =
  ## Render the complete entry modal
  let modal = newModal()
    .title("E C 4 X")
    .maxWidth(ModalMaxWidth)
    .minWidth(ModalMinWidth)
    .minHeight(ModalMinHeight)
  
  let desiredHeight = desiredGamesHeight(state)
  let fixedHeight = calculateContentHeight(state, 0)
  let minGamesHeight = 2
  let maxContentHeight = viewport.height - FooterHeight - 2
  let availableForGames = maxContentHeight - fixedHeight
  let maxGamesHeight = max(minGamesHeight, availableForGames)
  let gamesHeight = max(minGamesHeight,
    min(desiredHeight, maxGamesHeight))
  let contentHeight = fixedHeight + gamesHeight
  let modalArea = modal.calculateArea(viewport, contentHeight + FooterHeight)
  
  # Render modal frame with footer separator
  modal.renderWithSeparator(modalArea, buf, FooterHeight)
  
  # Get inner content area
  let inner = modal.inner(modalArea)
  
  if state.mode == EntryModalMode.ImportNsec:
    renderImportMode(buf, inner, modalArea,
                     state.importInput, state.importError, state.importMasked)
  elif state.mode == EntryModalMode.PasswordPrompt:
    renderPasswordPromptMode(buf, inner, modalArea,
                             state.passwordInput, state.importError, state.importMasked)
  elif state.mode == EntryModalMode.CreateGame:
    renderCreateGameMode(buf, inner, modalArea, state)
  elif state.mode == EntryModalMode.ManageGames:
    # TODO: Implement manage games mode
    renderImportMode(buf, inner, modalArea,
                     state.importInput, "Manage Games: Not implemented", state.importMasked)
  else:
    # Normal mode
    var y = inner.y + 1  # Space after title bar
    
    # Logo
    let logoArea = rect(inner.x, y, inner.width, LogoHeight)
    renderLogo(buf, logoArea)
    y += LogoHeight + 1
    
    # Identity section
    let identityArea = rect(inner.x, y, inner.width, 2)
    renderIdentitySection(buf, identityArea, state.identity,
      state.wallet.activeIdx, state.identityCount(), true)
    y += 2 + 1
    
    # Your Games section
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
                       state.focus == EntryModalFocus.RelayUrl, state.nostrStatus)
    
    # Footer
    let footerArea = rect(inner.x, modalArea.bottom - 2, inner.width, 1)
    renderFooter(buf, footerArea, state.focus, state.isAdmin)
