## TUI Model - Application state for EC4X TUI
##
## This module defines the complete application model for the TUI player,
## combining both game state and UI state into a single structure that
## the SAM pattern can manage.
##
## The model is the single source of truth for the entire application.
##
## EC4X TUI has 9 primary views accessible via number keys [1-9]:
##   1. Overview   - Empire dashboard, leaderboard, alerts
##   2. Planets    - Colony list and management
##   3. Fleets     - Fleet console (system/list view)
##   4. Research   - Tech levels, ERP/SRP/TRP allocation
##   5. Espionage  - EBP/CIP budget, intel operations
##   6. Economy    - Tax rate, treasury, income
##   7. Reports    - Turn summaries, combat/intel reports
##   8. Messages   - Diplomacy, inter-house communication
##   9. Settings   - Display options, automation defaults

import std/[options, tables, algorithm]
import ../tui/widget/scroll_state
import ../tui/widget/entry_modal
import ../state/identity

export entry_modal
export identity

# =============================================================================
# Fleet Command Constants (from 06-operations.md)
# =============================================================================

const
  CmdHold* = 0            ## Hold position, await commands
  CmdMove* = 1            ## Move to destination
  CmdSeekHome* = 2        ## Return to drydock
  CmdPatrol* = 3          ## Patrol single system
  CmdGuardStarbase* = 4   ## Guard starbase
  CmdGuardColony* = 5     ## Guard colony
  CmdBlockade* = 6        ## Blockade planet
  CmdBombard* = 7         ## Orbital bombardment
  CmdInvade* = 8          ## Ground invasion
  CmdBlitz* = 9           ## Rapid assault
  CmdColonize* = 10       ## Establish colony
  CmdScoutColony* = 11    ## Scout intel on colony
  CmdScoutSystem* = 12    ## Scout intel on system
  CmdHackStarbase* = 13   ## Cyber op on starbase
  CmdJoinFleet* = 14      ## Merge into target fleet
  CmdRendezvous* = 15     ## Move and auto-merge
  CmdSalvage* = 16        ## Scrap fleet for 50% PP
  CmdReserve* = 17        ## 50% readiness, 50% cost
  CmdMothball* = 18       ## Offline, 10% cost, 0 CC
  CmdView* = 19           ## Long-range recon

proc commandLabel*(cmdNum: int): string =
  ## Get human-readable label for fleet command
  case cmdNum
  of CmdHold: "Hold"
  of CmdMove: "Move"
  of CmdSeekHome: "Seek Home"
  of CmdPatrol: "Patrol"
  of CmdGuardStarbase: "Guard SB"
  of CmdGuardColony: "Guard Col"
  of CmdBlockade: "Blockade"
  of CmdBombard: "Bombard"
  of CmdInvade: "Invade"
  of CmdBlitz: "Blitz"
  of CmdColonize: "Colonize"
  of CmdScoutColony: "Scout Col"
  of CmdScoutSystem: "Scout Sys"
  of CmdHackStarbase: "Hack SB"
  of CmdJoinFleet: "Join Fleet"
  of CmdRendezvous: "Rendezvous"
  of CmdSalvage: "Salvage"
  of CmdReserve: "Reserve"
  of CmdMothball: "Mothball"
  of CmdView: "View"
  else: "Unknown"

type
  ViewMode* {.pure.} = enum
    ## Current UI view (maps to hotkey number)
    ##
    ## Primary views [1-9]:
    Overview = 1      ## [1] Strategic dashboard
    Planets = 2       ## [2] Colony management
    Fleets = 3        ## [3] Fleet console
    Research = 4      ## [4] Tech & research
    Espionage = 5     ## [5] Intel operations
    Economy = 6       ## [6] Tax & treasury
    Reports = 7       ## [7] Turn reports
    Messages = 8      ## [8] Diplomacy
    Settings = 9      ## [9] Game settings
    # Sub-views (not directly accessible via number keys)
    PlanetDetail = 20 ## Planet detail (Summary/Economy/Construction/etc.)
    FleetDetail = 30  ## Fleet detail view
    ReportDetail = 70 ## Report detail view

# Legacy aliases for backward compatibility
const
  Colonies* = ViewMode.Planets    ## Legacy alias for Planets
  Map* = ViewMode.Overview        ## Legacy: Map mode (now part of Overview)
  Orders* = ViewMode.Fleets       ## Legacy: Orders (now part of Fleets)
  Systems* = ViewMode.Overview    ## Legacy: Systems (now part of Overview)

type
  # Re-export hex coordinate for convenience
  HexCoord* = tuple[q, r: int]

  HexDirection* {.pure.} = enum
    ## Movement directions on hex grid
    East, NorthEast, NorthWest, West, SouthWest, SouthEast

  SystemInfo* = object
    ## Minimal system info for rendering (decoupled from engine types)
    id*: int
    name*: string
    coords*: HexCoord
    ring*: int
    planetClass*: int       ## 0=Extreme to 6=Eden
    resourceRating*: int    ## 0=VeryPoor to 4=VeryRich
    owner*: Option[int]     ## House ID if colonized
    isHomeworld*: bool
    isHub*: bool
    fleetCount*: int        ## Number of fleets present

  ColonyInfo* = object
    ## Colony info for list display
    systemId*: int
    systemName*: string
    population*: int
    production*: int
    owner*: int

  FleetInfo* = object
    ## Fleet info for list display
    id*: int
    location*: int          ## System ID
    locationName*: string
    shipCount*: int
    owner*: int
    command*: int           ## Fleet command (0-19, see 06-operations.md)
    commandLabel*: string   ## Human-readable command ("Hold", "Move", "Patrol")
    isIdle*: bool           ## True if command is Hold (00)

  CommandInfo* = object
    ## Fleet command info (renamed from OrderInfo)
    fleetId*: int
    commandType*: int       ## Command number (0-19)
    description*: string

  MapState* = object
    ## Hex map navigation state
    cursor*: HexCoord
    selected*: Option[HexCoord]
    viewportOrigin*: HexCoord

  BreadcrumbItem* = object
    ## A single breadcrumb segment for navigation
    label*: string
    viewMode*: ViewMode
    entityId*: int              ## Entity ID for drill-down (colony/fleet ID)

  PlanetDetailTab* {.pure.} = enum
    ## Tabs in planet detail view
    Summary = 1
    Economy = 2
    Construction = 3
    Defense = 4
    Settings = 5

  FleetViewMode* {.pure.} = enum
    ## Fleet console sub-modes
    SystemView    ## Grouped by location
    ListView      ## Flat list with multi-select

  ReportCategory* {.pure.} = enum
    ## Report category for inbox filtering
    Summary
    Combat
    Intelligence
    Economy
    Diplomacy
    Operations
    Other

  ReportEntry* = object
    ## Narrative report entry for Reports view
    id*: int
    turn*: int
    category*: ReportCategory
    title*: string
    summary*: string
    detail*: seq[string]
    isUnread*: bool
    linkView*: int
    linkLabel*: string

  AppPhase* {.pure.} = enum
    Lobby
    InGame

  LobbyPane* {.pure.} = enum
    Profile
    ActiveGames
    JoinGames

  LobbyInputMode* {.pure.} = enum
    None
    Pubkey
    Name

  JoinGameInfo* = object
    id*: string
    name*: string
    turn*: int
    phase*: string
    playerCount*: int
    assignedCount*: int

  ActiveGameInfo* = object
    id*: string
    name*: string
    turn*: int
    phase*: string
    houseId*: int

  JoinStatus* {.pure.} = enum
    Idle
    SelectingGame
    EnteringPubkey
    EnteringName
    WaitingResponse
    Joined
    Failed

  TurnBucket* = object
    ## Reports grouped by turn for inbox display
    turn*: int
    unreadCount*: int
    reports*: seq[ReportEntry]

  ReportPaneFocus* {.pure.} = enum
    ## Focused pane in reports view
    TurnList
    SubjectList
    BodyPane

  # ============================================================================
  # The Complete TUI Model
  # ============================================================================

  TuiModel* = object
    ## Complete application state for TUI player

    # -------------
    # UI State
    # -------------
    appPhase*: AppPhase           ## Lobby or in-game mode
    mode*: ViewMode               ## Current view mode
    previousMode*: ViewMode       ## Previous mode (for back navigation)
    selectedIdx*: int             ## Selected index in current list
    mapState*: MapState           ## Hex map navigation state

    # Lobby state
    lobbyPane*: LobbyPane
    lobbyInputMode*: LobbyInputMode
    lobbySelectedIdx*: int
    lobbyProfilePubkey*: string
    lobbyProfileName*: string
    lobbySessionKeyActive*: bool
    lobbyWarning*: string
    lobbyActiveGames*: seq[ActiveGameInfo]
    lobbyJoinGames*: seq[JoinGameInfo]
    lobbyJoinSelectedIdx*: int
    lobbyJoinStatus*: JoinStatus
    lobbyJoinError*: string
    lobbyJoinRequestPath*: string
    lobbyGameId*: string

    loadGameRequested*: bool
    loadGameId*: string
    loadHouseId*: int

    # Breadcrumb navigation
    breadcrumbs*: seq[BreadcrumbItem]

    # Sub-view state
    planetDetailTab*: PlanetDetailTab   ## Current tab in planet detail
    fleetViewMode*: FleetViewMode       ## System view vs List view
    selectedFleetIds*: seq[int]         ## Multi-select for fleet batch ops

    # Expert mode state
    expertModeActive*: bool       ## Expert mode (: prompt) active
    expertModeInput*: string      ## Current expert mode input
    expertModeHistory*: seq[string]  ## Command history
    expertModeHistoryIdx*: int    ## Current history position
    expertModeFeedback*: string   ## Feedback for expert commands

    # Order entry state (for keybindings + target selection flow)
    orderEntryActive*: bool       ## In target selection mode for order
    orderEntryFleetId*: int       ## Fleet being given orders
    orderEntryCommandType*: int   ## Command type (CmdMove, CmdPatrol, etc.)
    orderEntryPreviousMode*: ViewMode  ## Mode to return to on cancel/confirm

    # Pending order (set by acceptor, processed by main loop)
    pendingFleetOrderFleetId*: int
    pendingFleetOrderCommandType*: int
    pendingFleetOrderTargetSystemId*: int  ## 0 = no target (for Hold)
    pendingFleetOrderReady*: bool          ## True when order ready to write

    # Terminal dimensions
    termWidth*: int
    termHeight*: int

    # Status flags
    running*: bool                ## Application running
    needsResize*: bool            ## Terminal was resized
    statusMessage*: string        ## Status bar message

    # Map export flags (processed by main loop with GameState access)
    exportMapRequested*: bool     ## Export SVG starmap
    openMapRequested*: bool       ## Export and open in viewer
    lastExportPath*: string       ## Path to last exported SVG

    # PlayerState cache (local, fog-of-war filtered)
    playerStateLoaded*: bool

    # -------------
    # Game Data (View Layer - decoupled from engine)
    # -------------
    turn*: int
    viewingHouse*: int            ## Player's house ID
    houseName*: string
    treasury*: int
    prestige*: int
    prestigeRank*: int            ## Rank among all houses (1=first)
    totalHouses*: int             ## Total number of houses in game
    production*: int              ## Net House Value (production income)
    commandUsed*: int             ## Current command capacity used
    commandMax*: int              ## Maximum command capacity
    alertCount*: int              ## Number of alerts/warnings
    unreadReports*: int           ## Unread reports
    unreadMessages*: int          ## Unread diplomatic messages

    # Collections for display
    systems*: Table[HexCoord, SystemInfo]
    colonies*: seq[ColonyInfo]
    fleets*: seq[FleetInfo]
    commands*: seq[CommandInfo]    ## Fleet commands (renamed from orders)

    maxRing*: int                 ## Max ring for starmap
    homeworld*: Option[HexCoord]  ## Player's homeworld location

    # Detail view entity tracking
    selectedColonyId*: int        ## Colony ID for planet detail view
    selectedFleetId*: int         ## Fleet ID for fleet detail view
    selectedReportId*: int        ## Report ID for report detail view
    reportFilter*: ReportCategory ## Active report filter
    reports*: seq[ReportEntry]    ## Report inbox entries
    reportFocus*: ReportPaneFocus ## Focused reports pane
    reportTurnIdx*: int           ## Selected turn index
    reportSubjectIdx*: int        ## Selected subject index
    reportTurnScroll*: ScrollState
    reportSubjectScroll*: ScrollState
    reportBodyScroll*: ScrollState

    # Entry modal state (replaces legacy lobby UI)
    entryModal*: EntryModalState


# =============================================================================
# Model Initialization
# =============================================================================

proc hexCoord*(q, r: int): HexCoord =
  ## Create a hex coordinate
  (q, r)

proc initMapState*(cursor: HexCoord = (0, 0)): MapState =
  ## Create initial map state
  MapState(
    cursor: cursor,
    selected: none(HexCoord),
    viewportOrigin: (0, 0)
  )

proc initBreadcrumb*(label: string, mode: ViewMode,
                     entityId: int = 0): BreadcrumbItem =
  ## Create a breadcrumb item
  BreadcrumbItem(label: label, viewMode: mode, entityId: entityId)

proc initTuiModel*(): TuiModel =
  ## Create initial TUI model with defaults
  TuiModel(
    appPhase: AppPhase.Lobby,
    mode: ViewMode.Overview,
    previousMode: ViewMode.Overview,
    selectedIdx: 0,
    mapState: initMapState(),
    breadcrumbs: @[initBreadcrumb("Home", ViewMode.Overview)],
    lobbyPane: LobbyPane.Profile,
    lobbyInputMode: LobbyInputMode.None,
    lobbySelectedIdx: 0,
    lobbyProfilePubkey: "",
    lobbyProfileName: "",
    lobbySessionKeyActive: false,
    lobbyWarning: "",
    lobbyActiveGames: @[],
    lobbyJoinGames: @[],
    lobbyJoinSelectedIdx: 0,
    lobbyJoinStatus: JoinStatus.Idle,
    lobbyJoinError: "",
    lobbyJoinRequestPath: "",
    lobbyGameId: "",
    loadGameRequested: false,
    loadGameId: "",
    loadHouseId: 0,
    planetDetailTab: PlanetDetailTab.Summary,
    fleetViewMode: FleetViewMode.ListView,
    selectedFleetIds: @[],
    expertModeActive: false,
    expertModeInput: "",
    expertModeHistory: @[],
    expertModeHistoryIdx: 0,
    expertModeFeedback: "",
    orderEntryActive: false,
    orderEntryFleetId: 0,
    orderEntryCommandType: 0,
    orderEntryPreviousMode: ViewMode.Fleets,
    pendingFleetOrderFleetId: 0,
    pendingFleetOrderCommandType: 0,
    pendingFleetOrderTargetSystemId: 0,
    pendingFleetOrderReady: false,
    termWidth: 80,
    termHeight: 24,
    running: true,
    needsResize: false,
    statusMessage: "",
    playerStateLoaded: false,
    turn: 1,
    viewingHouse: 1,
    houseName: "Unknown",
    treasury: 0,
    prestige: 0,
    prestigeRank: 0,
    totalHouses: 0,
    production: 0,
    commandUsed: 0,
    commandMax: 0,
    alertCount: 0,
    unreadReports: 0,
    unreadMessages: 0,
    systems: initTable[HexCoord, SystemInfo](),
    colonies: @[],
    fleets: @[],
    commands: @[],
    maxRing: 3,
    homeworld: none(HexCoord),
    selectedColonyId: 0,
    selectedFleetId: 0,
    selectedReportId: 0,
    reportFilter: ReportCategory.Summary,
    reportFocus: ReportPaneFocus.TurnList,
    reportTurnIdx: 0,
    reportSubjectIdx: 0,
    reportTurnScroll: initScrollState(),
    reportSubjectScroll: initScrollState(),
    reportBodyScroll: initScrollState(),
    entryModal: newEntryModalState(),
    reports: @[
      ReportEntry(
        id: 1,
        turn: 42,
        category: ReportCategory.Combat,
        title: "Skirmish at Thera Gate",
        summary: "Fleet Sigma repelled pirates near Thera Gate.",
        detail: @[
          "Fleet Sigma intercepted pirate raiders.",
          "2 enemy ships destroyed, no losses.",
          "System remains secure."
        ],
        isUnread: true,
        linkView: 3,
        linkLabel: "Fleets"
      ),
      ReportEntry(
        id: 2,
        turn: 42,
        category: ReportCategory.Economy,
        title: "Income Report",
        summary: "Net income 640 PP. Tax rate 52%.",
        detail: @[
          "Gross colony output: 1,180 PP.",
          "Net house value: 640 PP.",
          "High tax rate penalty applied."
        ],
        isUnread: false,
        linkView: 6,
        linkLabel: "Economy"
      ),
      ReportEntry(
        id: 3,
        turn: 41,
        category: ReportCategory.Intelligence,
        title: "Scout Report: Nova",
        summary: "Scout Lambda reports enemy activity in Nova.",
        detail: @[
          "Detected 2 enemy fleets in orbit.",
          "Starbase level estimated at 1.",
          "Further intel recommended."
        ],
        isUnread: true,
        linkView: 7,
        linkLabel: "Reports"
      ),
      ReportEntry(
        id: 4,
        turn: 41,
        category: ReportCategory.Diplomacy,
        title: "Proposal: De-escalation",
        summary: "House Lyra requests neutral status.",
        detail: @[
          "Proposal to de-escalate from Hostile to Neutral.",
          "Expires on turn 43.",
          "Open diplomacy screen to respond."
        ],
        isUnread: false,
        linkView: 8,
        linkLabel: "Messages"
      ),
      ReportEntry(
        id: 5,
        turn: 40,
        category: ReportCategory.Summary,
        title: "Turn Summary",
        summary: "3 fleets awaiting orders. 1 idle shipyard.",
        detail: @[
          "Bigun shipyard idle.",
          "Fleet Omicron awaiting orders.",
          "Fleet Tau awaiting orders."
        ],
        isUnread: false,
        linkView: 1,
        linkLabel: "Overview"
      )
    ]
  )

# =============================================================================
# Hex Navigation Helpers
# =============================================================================

proc neighbor*(coord: HexCoord, dir: HexDirection): HexCoord =
  ## Get neighboring hex in given direction
  ## Uses axial coordinates with flat-top orientation
  case dir
  of HexDirection.East:       (coord.q + 1, coord.r)
  of HexDirection.West:       (coord.q - 1, coord.r)
  of HexDirection.NorthEast:  (coord.q + 1, coord.r - 1)
  of HexDirection.NorthWest:  (coord.q, coord.r - 1)
  of HexDirection.SouthEast:  (coord.q, coord.r + 1)
  of HexDirection.SouthWest:  (coord.q - 1, coord.r + 1)

# =============================================================================
# Model Queries
# =============================================================================

proc reportCategoryLabel*(category: ReportCategory): string =
  ## Label for report category
  case category
  of ReportCategory.Summary: "Summary"
  of ReportCategory.Combat: "Combat"
  of ReportCategory.Intelligence: "Intel"
  of ReportCategory.Economy: "Economy"
  of ReportCategory.Diplomacy: "Diplomacy"
  of ReportCategory.Operations: "Ops"
  of ReportCategory.Other: "Other"

proc reportPaneLabel*(focus: ReportPaneFocus): string =
  ## Label for focused report pane
  case focus
  of ReportPaneFocus.TurnList: "Turns"
  of ReportPaneFocus.SubjectList: "Subjects"
  of ReportPaneFocus.BodyPane: "Body"

proc filteredReports*(model: TuiModel): seq[ReportEntry] =
  ## Filter reports by active category
  result = @[]
  for report in model.reports:
    if report.category == model.reportFilter:
      result.add(report)

proc reportsByTurn*(model: TuiModel): seq[TurnBucket] =
  ## Group reports by turn (newest first).
  var buckets = initTable[int, TurnBucket]()
  for report in model.filteredReports():
    if not buckets.hasKey(report.turn):
      buckets[report.turn] = TurnBucket(
        turn: report.turn,
        unreadCount: 0,
        reports: @[]
      )
    var bucket = buckets[report.turn]
    bucket.reports.add(report)
    if report.isUnread:
      bucket.unreadCount += 1
    buckets[report.turn] = bucket

  result = @[]
  for turn, bucket in buckets.pairs:
    result.add(bucket)
  result.sort(proc(a, b: TurnBucket): int =
    if a.turn == b.turn:
      0
    elif a.turn > b.turn:
      -1
    else:
      1
  )

proc currentTurnReports*(model: TuiModel): seq[ReportEntry] =
  ## Reports for the selected turn.
  let buckets = model.reportsByTurn()
  if buckets.len == 0:
    return @[]
  let turnIdx = max(0, min(model.reportTurnIdx, buckets.len - 1))
  result = buckets[turnIdx].reports

proc currentReport*(model: TuiModel): Option[ReportEntry] =
  ## Current report based on subject selection.
  let reports = model.currentTurnReports()
  if reports.len == 0:
    return none(ReportEntry)
  let subjectIdx = max(0, min(model.reportSubjectIdx, reports.len - 1))
  some(reports[subjectIdx])

proc reportCategoryKey*(category: ReportCategory): char =
  ## Short key hint for report category
  case category
  of ReportCategory.Summary: 'S'
  of ReportCategory.Combat: 'C'
  of ReportCategory.Intelligence: 'I'
  of ReportCategory.Economy: 'E'
  of ReportCategory.Diplomacy: 'D'
  of ReportCategory.Operations: 'O'
  of ReportCategory.Other: 'X'

proc selectedReport*(model: TuiModel): Option[ReportEntry] =
  ## Get selected report by index
  let reports = model.filteredReports()
  if reports.len == 0:
    return none(ReportEntry)
  if model.selectedReportId != 0:
    for report in reports:
      if report.id == model.selectedReportId:
        return some(report)
  if model.selectedIdx < reports.len:
    return some(reports[model.selectedIdx])
  none(ReportEntry)

proc currentListLength*(model: TuiModel): int =
  ## Get length of current list based on mode
  if model.appPhase == AppPhase.Lobby:
    case model.lobbyPane
    of LobbyPane.ActiveGames:
      return model.lobbyActiveGames.len
    of LobbyPane.JoinGames:
      return model.lobbyJoinGames.len
    of LobbyPane.Profile:
      return 0
  case model.mode
  of ViewMode.Overview: 0  # Overview has no list selection
  of ViewMode.Planets: model.colonies.len
  of ViewMode.Fleets: model.fleets.len
  of ViewMode.Research: 0  # Research has no list
  of ViewMode.Espionage: 0  # Espionage operations list (TODO)
  of ViewMode.Economy: 0   # Economy has no list
  of ViewMode.Reports: model.filteredReports().len
  of ViewMode.Messages: 0  # TODO: messages list
  of ViewMode.Settings: 0  # TODO: settings list
  of ViewMode.PlanetDetail: 0
  of ViewMode.FleetDetail: 0
  of ViewMode.ReportDetail: 0

proc idleFleetsCount*(model: TuiModel): int =
  ## Count fleets with Hold command (awaiting orders)
  result = 0
  for fleet in model.fleets:
    if fleet.isIdle:
      result.inc

proc systemAt*(model: TuiModel, coord: HexCoord): Option[SystemInfo] =
  ## Get system at coordinate
  if model.systems.hasKey(coord):
    some(model.systems[coord])
  else:
    none(SystemInfo)

proc cursorSystem*(model: TuiModel): Option[SystemInfo] =
  ## Get system at cursor
  model.systemAt(model.mapState.cursor)

proc selectedColony*(model: TuiModel): Option[ColonyInfo] =
  ## Get selected colony
  if model.mode == ViewMode.Planets and model.selectedIdx < model.colonies.len:
    some(model.colonies[model.selectedIdx])
  else:
    none(ColonyInfo)

proc selectedFleet*(model: TuiModel): Option[FleetInfo] =
  ## Get selected fleet
  if model.mode == ViewMode.Fleets and model.selectedIdx < model.fleets.len:
    some(model.fleets[model.selectedIdx])
  else:
    none(FleetInfo)

proc ownedColonyCoords*(model: TuiModel): seq[HexCoord] =
  ## Get coordinates of all owned colonies
  result = @[]
  for sys in model.systems.values:
    if sys.owner.isSome and sys.owner.get == model.viewingHouse:
      result.add(sys.coords)

# =============================================================================
# View Mode Helpers
# =============================================================================

proc viewModeKey*(mode: ViewMode): char =
  ## Get the hotkey for a view mode
  case mode
  of ViewMode.Overview: '1'
  of ViewMode.Planets: '2'
  of ViewMode.Fleets: '3'
  of ViewMode.Research: '4'
  of ViewMode.Espionage: '5'
  of ViewMode.Economy: '6'
  of ViewMode.Reports: '7'
  of ViewMode.Messages: '8'
  of ViewMode.Settings: '9'
  of ViewMode.PlanetDetail, ViewMode.FleetDetail, ViewMode.ReportDetail: '0'

proc viewModeLabel*(mode: ViewMode): string =
  ## Get the display label for a view mode
  case mode
  of ViewMode.Overview: "Overview"
  of ViewMode.Planets: "Planets"
  of ViewMode.Fleets: "Fleets"
  of ViewMode.Research: "Research"
  of ViewMode.Espionage: "Espionage"
  of ViewMode.Economy: "Economy"
  of ViewMode.Reports: "Reports"
  of ViewMode.Messages: "Messages"
  of ViewMode.Settings: "Settings"
  of ViewMode.PlanetDetail: "Planet"
  of ViewMode.FleetDetail: "Fleet"
  of ViewMode.ReportDetail: "Report"

proc viewModeFromKey*(key: char): Option[ViewMode] =
  ## Get view mode from hotkey
  case key
  of '1': some(ViewMode.Overview)
  of '2': some(ViewMode.Planets)
  of '3': some(ViewMode.Fleets)
  of '4': some(ViewMode.Research)
  of '5': some(ViewMode.Espionage)
  of '6': some(ViewMode.Economy)
  of '7': some(ViewMode.Reports)
  of '8': some(ViewMode.Messages)
  of '9': some(ViewMode.Settings)
  else: none(ViewMode)

proc isPrimaryView*(mode: ViewMode): bool =
  ## Check if mode is a primary view (accessible via number keys)
  mode in {ViewMode.Overview, ViewMode.Planets, ViewMode.Fleets,
           ViewMode.Research, ViewMode.Espionage, ViewMode.Economy,
           ViewMode.Reports, ViewMode.Messages, ViewMode.Settings}

proc isDetailView*(mode: ViewMode): bool =
  ## Check if mode is a detail/drill-down view
  mode in {ViewMode.PlanetDetail, ViewMode.FleetDetail, ViewMode.ReportDetail}

# =============================================================================
# Breadcrumb Helpers
# =============================================================================

proc pushBreadcrumb*(model: var TuiModel, label: string, mode: ViewMode,
                     entityId: int = 0) =
  ## Push a new breadcrumb onto the navigation stack
  model.breadcrumbs.add(initBreadcrumb(label, mode, entityId))

proc popBreadcrumb*(model: var TuiModel): bool =
  ## Pop the last breadcrumb, returns false if at root
  if model.breadcrumbs.len > 1:
    model.breadcrumbs.setLen(model.breadcrumbs.len - 1)
    return true
  return false

proc resetBreadcrumbs*(model: var TuiModel, mode: ViewMode) =
  ## Reset breadcrumbs to a primary view
  model.breadcrumbs = @[initBreadcrumb("Home", ViewMode.Overview)]
  if mode != ViewMode.Overview:
    model.breadcrumbs.add(initBreadcrumb(mode.viewModeLabel, mode))

proc currentBreadcrumb*(model: TuiModel): BreadcrumbItem =
  ## Get the current (last) breadcrumb
  if model.breadcrumbs.len > 0:
    model.breadcrumbs[^1]
  else:
    initBreadcrumb("Home", ViewMode.Overview)

proc breadcrumbDepth*(model: TuiModel): int =
  ## Get breadcrumb depth
  model.breadcrumbs.len

# =============================================================================
# Multi-Select Helpers (for Fleet batch operations)
# =============================================================================

proc toggleFleetSelection*(model: var TuiModel, fleetId: int) =
  ## Toggle fleet selection for batch operations
  let idx = model.selectedFleetIds.find(fleetId)
  if idx >= 0:
    model.selectedFleetIds.delete(idx)
  else:
    model.selectedFleetIds.add(fleetId)

proc clearFleetSelection*(model: var TuiModel) =
  ## Clear all fleet selections
  model.selectedFleetIds.setLen(0)

proc isFleetSelected*(model: TuiModel, fleetId: int): bool =
  ## Check if a fleet is selected
  fleetId in model.selectedFleetIds

proc selectedFleetCount*(model: TuiModel): int =
  ## Get number of selected fleets
  model.selectedFleetIds.len

# =============================================================================
# Expert Mode Helpers
# =============================================================================

proc clearExpertFeedback*(model: var TuiModel) =
  ## Clear expert mode feedback message
  model.expertModeFeedback = ""

proc enterExpertMode*(model: var TuiModel) =
  ## Enter expert mode
  model.expertModeActive = true
  model.expertModeInput = ""
  model.clearExpertFeedback()

proc exitExpertMode*(model: var TuiModel) =
  ## Exit expert mode
  model.expertModeActive = false
  model.expertModeInput = ""

proc setExpertFeedback*(model: var TuiModel, message: string) =
  ## Update expert mode feedback message
  model.expertModeFeedback = message

proc addToExpertHistory*(model: var TuiModel, command: string) =
  ## Add command to expert mode history
  if command.len > 0:
    model.expertModeHistory.add(command)
    model.expertModeHistoryIdx = model.expertModeHistory.len

# =============================================================================
# Order Entry Helpers
# =============================================================================

proc startOrderEntry*(model: var TuiModel, fleetId: int, cmdType: int) =
  ## Begin order entry mode for a fleet
  model.orderEntryActive = true
  model.orderEntryFleetId = fleetId
  model.orderEntryCommandType = cmdType
  model.orderEntryPreviousMode = model.mode
  # Switch to Overview (map) for target selection
  model.mode = ViewMode.Overview
  model.statusMessage = "Select target: [arrows] move | [Enter] confirm | [Esc] cancel"

proc cancelOrderEntry*(model: var TuiModel) =
  ## Cancel order entry and return to previous view
  model.orderEntryActive = false
  model.mode = model.orderEntryPreviousMode
  model.mapState.selected = none(HexCoord)
  model.statusMessage = "Order cancelled"

proc confirmOrderEntry*(model: var TuiModel, targetSystemId: int) =
  ## Confirm order entry and queue the order for writing
  model.pendingFleetOrderFleetId = model.orderEntryFleetId
  model.pendingFleetOrderCommandType = model.orderEntryCommandType
  model.pendingFleetOrderTargetSystemId = targetSystemId
  model.pendingFleetOrderReady = true
  model.orderEntryActive = false
  model.mode = model.orderEntryPreviousMode
  model.mapState.selected = none(HexCoord)

proc queueImmediateOrder*(model: var TuiModel, fleetId: int, cmdType: int) =
  ## Queue an immediate order (no target needed, like Hold)
  model.pendingFleetOrderFleetId = fleetId
  model.pendingFleetOrderCommandType = cmdType
  model.pendingFleetOrderTargetSystemId = 0
  model.pendingFleetOrderReady = true

proc clearPendingOrder*(model: var TuiModel) =
  ## Clear the pending order after it's been processed
  model.pendingFleetOrderReady = false
  model.pendingFleetOrderFleetId = 0
  model.pendingFleetOrderCommandType = 0
  model.pendingFleetOrderTargetSystemId = 0

proc orderEntryNeedsTarget*(cmdType: int): bool =
  ## Check if a command type needs target selection
  cmdType in [CmdMove, CmdPatrol, CmdBlockade, CmdBombard, CmdInvade,
              CmdBlitz, CmdColonize, CmdScoutColony, CmdScoutSystem,
              CmdJoinFleet, CmdRendezvous]
