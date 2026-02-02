## TUI Model - Application state for EC4X TUI
##
## This module defines the complete application model for the TUI player,
## combining both game state and UI state into a single structure that
## the SAM pattern can manage.
##
## The model is the single source of truth for the entire application.
##
## EC4X TUI primary views (F-keys):
##   F1 Overview   - Empire dashboard, leaderboard, alerts
##   F2 Colony     - Colony list and management
##   F3 Fleets     - Fleet console (system/list view)
##   F4 Tech       - Tech levels, ERP/SRP/TRP allocation
##   F5 Espionage  - EBP/CIP budget, intel operations
##   F6 General    - Diplomacy, tax, empire policy
##   F7 Reports    - Turn summaries, combat/intel reports
##   F8 Settings   - Display options, automation defaults

import std/[options, tables, algorithm, strutils]
import ../tui/widget/scroll_state
import ../tui/widget/entry_modal
import ../state/identity
import ../../engine/types/[core, fleet, production, command, tech, ship,
  facilities, ground_unit]

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

const
  FleetDetailVerticalMargin* = 6
  FleetDetailInfoHeight* = 4
  FleetDetailSeparatorHeight* = 1
  FleetDetailShipsHeaderHeight* = 1
  FleetDetailFooterHeight* = 2
  FleetDetailTableBaseHeight* = 4

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

proc fleetCommandNumber*(cmdType: FleetCommandType): int =
  ## Map FleetCommandType to command number
  case cmdType
  of FleetCommandType.Hold: CmdHold
  of FleetCommandType.Move: CmdMove
  of FleetCommandType.SeekHome: CmdSeekHome
  of FleetCommandType.Patrol: CmdPatrol
  of FleetCommandType.GuardStarbase: CmdGuardStarbase
  of FleetCommandType.GuardColony: CmdGuardColony
  of FleetCommandType.Blockade: CmdBlockade
  of FleetCommandType.Bombard: CmdBombard
  of FleetCommandType.Invade: CmdInvade
  of FleetCommandType.Blitz: CmdBlitz
  of FleetCommandType.Colonize: CmdColonize
  of FleetCommandType.ScoutColony: CmdScoutColony
  of FleetCommandType.ScoutSystem: CmdScoutSystem
  of FleetCommandType.HackStarbase: CmdHackStarbase
  of FleetCommandType.JoinFleet: CmdJoinFleet
  of FleetCommandType.Rendezvous: CmdRendezvous
  of FleetCommandType.Salvage: CmdSalvage
  of FleetCommandType.Reserve: CmdReserve
  of FleetCommandType.Mothball: CmdMothball
  of FleetCommandType.View: CmdView

proc fleetCommandCode*(cmdType: FleetCommandType): string =
  ## Get two-digit command code
  let cmdNum = fleetCommandNumber(cmdType)
  if cmdNum < 10:
    "0" & $cmdNum
  else:
    $cmdNum

proc fleetCommandLabel*(cmdType: FleetCommandType): string =
  ## Get label for fleet command type
  commandLabel(fleetCommandNumber(cmdType))

proc fleetDetailMaxRows*(termHeight: int): int =
  let maxModalHeight = max(8, termHeight - FleetDetailVerticalMargin)
  let maxInnerHeight = max(1, maxModalHeight - 2)
  let baseInnerHeight = FleetDetailInfoHeight +
    FleetDetailSeparatorHeight + FleetDetailShipsHeaderHeight +
    FleetDetailFooterHeight + FleetDetailTableBaseHeight
  max(0, maxInnerHeight - baseInnerHeight)

type
  BuildOptionKind* {.pure.} = enum
    Ship
    Ground
    Facility

  BuildOption* = object
    kind*: BuildOptionKind
    name*: string
    cost*: int
    cstReq*: int

  DockSummary* = object
    constructionAvailable*: int
    constructionTotal*: int
    repairAvailable*: int
    repairTotal*: int

  BuildCategory* {.pure.} = enum
    Ships, Facilities, Ground

  BuildModalFocus* {.pure.} = enum
    CategoryTabs, BuildList, QueueList

  PendingBuildItem* = object
    buildType*: BuildType
    name*: string
    cost*: int
    quantity*: int
    shipClass*: Option[ShipClass]
    facilityClass*: Option[FacilityClass]
    groundClass*: Option[GroundClass]

  BuildModalState* = object
    active*: bool
    colonyId*: int
    colonyName*: string
    category*: BuildCategory
    focus*: BuildModalFocus
    selectedBuildIdx*: int
    selectedQueueIdx*: int
    pendingQueue*: seq[PendingBuildItem]
    quantityInput*: int  # For ship quantity (1-99)
    availableOptions*: seq[BuildOption]
    dockSummary*: DockSummary
    buildListScroll*: ScrollState
    queueScroll*: ScrollState

  FleetConsoleSystem* = object
    ## System with fleets for fleet console (cached from PlayerState)
    systemId*: int
    systemName*: string
    sectorLabel*: string
    fleetCount*: int

  FleetConsoleFleet* = object
    ## Fleet info for console list (cached from PlayerState)
    fleetId*: int
    shipCount*: int
    attackStrength*: int
    defenseStrength*: int
    troopTransports*: int
    etacs*: int
    commandLabel*: string
    destinationLabel*: string
    eta*: int
    roe*: int
    status*: string

  FleetSubModal* {.pure.} = enum
    ## Sub-modal states for fleet detail modal
    None
    CommandPicker
    ROEPicker
    ConfirmPrompt

  CommandCategory* {.pure.} = enum
    ## Command categories for organization in picker
    Movement    # Hold, Move, Seek Home, Patrol
    Defense     # Guard Starbase, Guard Colony, Blockade
    Combat      # Bombard, Invade, Blitz
    Colonial    # Colonize
    Intel       # Scout Colony, Scout System, Hack Starbase, View
    FleetOps    # Join Fleet, Rendezvous, Salvage
    Status      # Reserve, Mothball

  FleetDetailModalState* = object
    ## Fleet detail view state
    ## NOTE: 'active' field is deprecated - use ViewMode.FleetDetail instead
    ## This state object is kept for sub-modal tracking (Command/ROE pickers)
    active*: bool  # DEPRECATED: Check ViewMode.FleetDetail instead
    fleetId*: int
    subModal*: FleetSubModal
    commandCategory*: CommandCategory
    commandIdx*: int           # Index within filtered commands
    roeValue*: int             # 0-10
    confirmPending*: bool
    confirmMessage*: string
    pendingCommandType*: FleetCommandType  # For confirmation flow
    shipScroll*: ScrollState
    shipCount*: int

  ViewMode* {.pure.} = enum
    ## Current UI view (maps to primary view number)
    ##
    ## Primary views:
    Overview = 1      ## F1 Strategic dashboard
    Planets = 2       ## F2 Colony management
    Fleets = 3        ## F3 Fleet console
    Research = 4      ## F4 Tech & research
    Espionage = 5     ## F5 Intel operations
    Economy = 6       ## F6 General (tax/diplomacy)
    Reports = 7       ## F7 Turn reports
    Messages = 8      ## Deprecated
    Settings = 9      ## F8 Game settings
    # Sub-views (not directly accessible via primary hotkeys)
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
  StagedCommandKind* {.pure.} = enum
    Fleet
    Build
    Repair
    Scrap

  StagedCommandEntry* = object
    kind*: StagedCommandKind
    index*: int

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
    colonyId*: int
    systemId*: int
    systemName*: string
    sectorLabel*: string
    planetClass*: int
    populationUnits*: int
    industrialUnits*: int
    grossOutput*: int
    netValue*: int
    populationGrowthPu*: Option[float32]
    constructionDockAvailable*: int
    constructionDockTotal*: int
    repairDockAvailable*: int
    repairDockTotal*: int
    blockaded*: bool
    idleConstruction*: bool
    owner*: int

  PlanetRow* = object
    ## Colony row for Colony view table (owned only)
    systemId*: int
    colonyId*: Option[int]
    systemName*: string
    sectorLabel*: string
    classLabel*: string
    resourceLabel*: string
    pop*: Option[int]
    iu*: Option[int]
    gco*: Option[int]
    ncv*: Option[int]
    growthLabel*: string
    cdTotal*: Option[int]
    rdTotal*: Option[int]
    fleetCount*: int
    starbaseCount*: int
    groundCount*: int
    batteryCount*: int
    shieldPresent*: bool
    statusLabel*: string
    isOwned*: bool
    isHomeworld*: bool
    ring*: int
    coordLabel*: string
    hasAlert*: bool

  IntelRow* = object
    ## Intel DB row for starmap database
    systemId*: int
    systemName*: string
    sectorLabel*: string
    ownerName*: string
    intelLabel*: string
    ltuLabel*: string
    notes*: string

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
    roe*: int               ## Rules of Engagement (0-10)

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

  FleetConsoleFocus* {.pure.} = enum
    ## Fleet console pane focus (SystemView mode only)
    SystemsPane   ## Systems with fleets
    FleetsPane    ## Fleets at selected system
    ShipsPane     ## Ships in selected fleet

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

  QuitConfirmationChoice* {.pure.} = enum
    QuitStay
    QuitExit

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
  # UI State (interaction + transient)
  # ============================================================================

  TuiUiState* = object
    appPhase*: AppPhase
    mode*: ViewMode
    previousMode*: ViewMode
    selectedIdx*: int
    mapState*: MapState

    # Lobby UI
    lobbyPane*: LobbyPane
    lobbyInputMode*: LobbyInputMode
    lobbySelectedIdx*: int
    lobbyProfilePubkey*: string
    lobbyProfileName*: string
    lobbySessionKeyActive*: bool
    lobbyWarning*: string
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
    planetDetailTab*: PlanetDetailTab
    fleetViewMode*: FleetViewMode
    selectedFleetIds*: seq[int]
    selectedColonyId*: int
    selectedFleetId*: int
    selectedReportId*: int

    # Fleet console state (SystemView mode)
    fleetConsoleFocus*: FleetConsoleFocus
    fleetConsoleSystemIdx*: int
    fleetConsoleFleetIdx*: int
    fleetConsoleShipIdx*: int
    fleetConsoleSystemScroll*: ScrollState
    fleetConsoleFleetScroll*: ScrollState
    fleetConsoleShipScroll*: ScrollState
    
    # Fleet console cached data (synced from PlayerState)
    fleetConsoleSystems*: seq[FleetConsoleSystem]
    fleetConsoleFleetsBySystem*: Table[int, seq[FleetConsoleFleet]]  # systemId -> fleets

    # Reports UI
    reportFilter*: ReportCategory
    reportFocus*: ReportPaneFocus
    reportTurnIdx*: int
    reportSubjectIdx*: int
    reportTurnScroll*: ScrollState
    reportSubjectScroll*: ScrollState
    reportBodyScroll*: ScrollState

    # Expert mode state
    expertModeActive*: bool
    expertModeInput*: string
    expertModeHistory*: seq[string]
    expertModeHistoryIdx*: int
    expertModeFeedback*: string
    expertPaletteSelection*: int

    # Order entry state
    orderEntryActive*: bool
    orderEntryFleetId*: int
    orderEntryCommandType*: int
    orderEntryPreviousMode*: ViewMode

    # Pending order (set by acceptor)
    pendingFleetOrderFleetId*: int
    pendingFleetOrderCommandType*: int
    pendingFleetOrderTargetSystemId*: int
    pendingFleetOrderReady*: bool

    # Staged commands (for turn submission)
    stagedFleetCommands*: seq[FleetCommand]
    stagedBuildCommands*: seq[BuildCommand]
    stagedRepairCommands*: seq[RepairCommand]
    stagedScrapCommands*: seq[ScrapCommand]
    turnSubmissionRequested*: bool
    turnSubmissionPending*: bool
    turnSubmissionConfirmed*: bool

    # Terminal dimensions
    termWidth*: int
    termHeight*: int

    # Status flags
    running*: bool
    needsResize*: bool
    statusMessage*: string
    quitConfirmationActive*: bool
    quitConfirmationChoice*: QuitConfirmationChoice

    # Map export flags
    exportMapRequested*: bool
    openMapRequested*: bool
    lastExportPath*: string

    # Nostr sync UI
    nostrEnabled*: bool
    nostrRelayUrl*: string
    nostrLastError*: string
    nostrStatus*: string
    nostrJoinRequested*: bool
    nostrJoinSent*: bool
    nostrJoinInviteCode*: string
    nostrJoinRelayUrl*: string
    nostrJoinGameId*: string
    nostrJoinPubkey*: string

    # Scroll states for primary views
    overviewScroll*: ScrollState
    planetsScroll*: ScrollState
    fleetsScroll*: ScrollState
    researchScroll*: ScrollState
    espionageScroll*: ScrollState
    economyScroll*: ScrollState
    messagesScroll*: ScrollState
    settingsScroll*: ScrollState

    # Entry modal state (replaces legacy lobby UI)
    entryModal*: EntryModalState

    # Build modal state
    buildModal*: BuildModalState

    # Fleet detail modal state
    fleetDetailModal*: FleetDetailModalState

  # ============================================================================
  # View State (render-only data)
  # ============================================================================

  TuiViewState* = object
    playerStateLoaded*: bool

    # House and turn data
    turn*: int
    viewingHouse*: int
    houseName*: string
    treasury*: int
    prestige*: int
    prestigeRank*: int
    totalHouses*: int
    production*: int
    houseTaxRate*: int
    commandUsed*: int
    commandMax*: int
    alertCount*: int
    unreadReports*: int
    unreadMessages*: int

    # Collections for display
    systems*: Table[HexCoord, SystemInfo]
    colonies*: seq[ColonyInfo]
    planetsRows*: seq[PlanetRow]
    intelRows*: seq[IntelRow]
    fleets*: seq[FleetInfo]
    commands*: seq[CommandInfo]
    reports*: seq[ReportEntry]

    maxRing*: int
    homeworld*: Option[HexCoord]

    # Lobby data lists
    lobbyActiveGames*: seq[ActiveGameInfo]
    lobbyJoinGames*: seq[JoinGameInfo]

  # ============================================================================
  # The Complete TUI Model (SAM wrapper)
  # ============================================================================

  TuiModel* = object
    ui*: TuiUiState
    view*: TuiViewState


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

proc initTuiUiState*(): TuiUiState =
  ## Create initial UI state with defaults
  TuiUiState(
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
    selectedColonyId: 0,
    selectedFleetId: 0,
    selectedReportId: 0,
    fleetConsoleFocus: FleetConsoleFocus.SystemsPane,
    fleetConsoleSystemIdx: 0,
    fleetConsoleFleetIdx: 0,
    fleetConsoleShipIdx: 0,
    fleetConsoleSystemScroll: initScrollState(),
    fleetConsoleFleetScroll: initScrollState(),
    fleetConsoleShipScroll: initScrollState(),
    fleetConsoleSystems: @[],
    fleetConsoleFleetsBySystem: initTable[int, seq[FleetConsoleFleet]](),
    reportFilter: ReportCategory.Summary,
    reportFocus: ReportPaneFocus.TurnList,
    reportTurnIdx: 0,
    reportSubjectIdx: 0,
    reportTurnScroll: initScrollState(),
    reportSubjectScroll: initScrollState(),
    reportBodyScroll: initScrollState(),
    expertModeActive: false,
    expertModeInput: "",
    expertModeHistory: @[],
    expertModeHistoryIdx: 0,
    expertModeFeedback: "",
    expertPaletteSelection: -1,
    orderEntryActive: false,
    orderEntryFleetId: 0,
    orderEntryCommandType: 0,
    orderEntryPreviousMode: ViewMode.Fleets,
    pendingFleetOrderFleetId: 0,
    pendingFleetOrderCommandType: 0,
    pendingFleetOrderTargetSystemId: 0,
    pendingFleetOrderReady: false,
    stagedFleetCommands: @[],
    stagedBuildCommands: @[],
    stagedRepairCommands: @[],
    stagedScrapCommands: @[],
    turnSubmissionRequested: false,
    turnSubmissionPending: false,
    turnSubmissionConfirmed: false,
    termWidth: 80,
    termHeight: 24,
    running: true,
    needsResize: false,
    statusMessage: "",
    quitConfirmationActive: false,
    quitConfirmationChoice: QuitStay,
    exportMapRequested: false,
    openMapRequested: false,
    lastExportPath: "",
    nostrEnabled: false,
    nostrRelayUrl: "",
    nostrLastError: "",
    nostrStatus: "idle",
    nostrJoinRequested: false,
    nostrJoinSent: false,
    nostrJoinInviteCode: "",
    nostrJoinRelayUrl: "",
    nostrJoinGameId: "",
    nostrJoinPubkey: "",
    overviewScroll: initScrollState(),
    planetsScroll: initScrollState(),
    fleetsScroll: initScrollState(),
    researchScroll: initScrollState(),
    espionageScroll: initScrollState(),
    economyScroll: initScrollState(),
    messagesScroll: initScrollState(),
    settingsScroll: initScrollState(),
    entryModal: newEntryModalState(),
    buildModal: BuildModalState(
      active: false,
      colonyId: 0,
      colonyName: "",
      category: BuildCategory.Ships,
      focus: BuildModalFocus.BuildList,
      selectedBuildIdx: 0,
      selectedQueueIdx: 0,
      pendingQueue: @[],
      quantityInput: 1,
      availableOptions: @[],
      buildListScroll: initScrollState(),
      queueScroll: initScrollState()
    ),
    fleetDetailModal: FleetDetailModalState(
      active: false,
      fleetId: 0,
      subModal: FleetSubModal.None,
      commandCategory: CommandCategory.Movement,
      commandIdx: 0,
      roeValue: 6,  # Standard ROE
      confirmPending: false,
      confirmMessage: "",
      pendingCommandType: FleetCommandType.Hold,
      shipScroll: initScrollState(),
      shipCount: 0
    )
  )

proc initTuiViewState*(): TuiViewState =
  ## Create initial view state with defaults
  TuiViewState(
    playerStateLoaded: false,
    turn: 1,
    viewingHouse: 1,
    houseName: "Unknown",
    treasury: 0,
    prestige: 0,
    prestigeRank: 0,
    totalHouses: 0,
    production: 0,
    houseTaxRate: 0,
    commandUsed: 0,
    commandMax: 0,
    alertCount: 0,
    unreadReports: 0,
    unreadMessages: 0,
    systems: initTable[HexCoord, SystemInfo](),
    colonies: @[],
    planetsRows: @[],
    intelRows: @[],
    fleets: @[],
    commands: @[],
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
        linkView: 9,
        linkLabel: "Settings"
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
    ],
    maxRing: 3,
    homeworld: none(HexCoord),
    lobbyActiveGames: @[],
    lobbyJoinGames: @[]
  )

proc initTuiModel*(): TuiModel =
  ## Create initial TUI model with defaults
  TuiModel(
    ui: initTuiUiState(),
    view: initTuiViewState()
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
  for report in model.view.reports:
    if report.category == model.ui.reportFilter:
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
  let turnIdx = max(0, min(model.ui.reportTurnIdx, buckets.len - 1))
  result = buckets[turnIdx].reports

proc currentReport*(model: TuiModel): Option[ReportEntry] =
  ## Current report based on subject selection.
  let reports = model.currentTurnReports()
  if reports.len == 0:
    return none(ReportEntry)
  let subjectIdx = max(0, min(model.ui.reportSubjectIdx, reports.len - 1))
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
  if model.ui.selectedReportId != 0:
    for report in reports:
      if report.id == model.ui.selectedReportId:
        return some(report)
  if model.ui.selectedIdx < reports.len:
    return some(reports[model.ui.selectedIdx])
  none(ReportEntry)

proc currentListLength*(model: TuiModel): int =
  ## Get length of current list based on mode
  if model.ui.appPhase == AppPhase.Lobby:
    case model.ui.lobbyPane
    of LobbyPane.ActiveGames:
      return model.view.lobbyActiveGames.len
    of LobbyPane.JoinGames:
      return model.view.lobbyJoinGames.len
    of LobbyPane.Profile:
      return 0
  case model.ui.mode
  of ViewMode.Overview: 0  # Overview has no list selection
  of ViewMode.Planets: model.view.planetsRows.len
  of ViewMode.Fleets: model.view.fleets.len
  of ViewMode.Research: 0  # Research has no list
  of ViewMode.Espionage: 0  # Espionage operations list (TODO)
  of ViewMode.Economy: 0   # Economy has no list
  of ViewMode.Reports: model.filteredReports().len
  of ViewMode.Messages: 0
  of ViewMode.Settings: 0  # TODO: settings list
  of ViewMode.PlanetDetail: 0
  of ViewMode.FleetDetail: 0
  of ViewMode.ReportDetail: 0

proc idleFleetsCount*(model: TuiModel): int =
  ## Count fleets with Hold command (awaiting orders)
  result = 0
  for fleet in model.view.fleets:
    if fleet.isIdle:
      result.inc

proc systemAt*(model: TuiModel, coord: HexCoord): Option[SystemInfo] =
  ## Get system at coordinate
  if model.view.systems.hasKey(coord):
    some(model.view.systems[coord])
  else:
    none(SystemInfo)

proc cursorSystem*(model: TuiModel): Option[SystemInfo] =
  ## Get system at cursor
  model.systemAt(model.ui.mapState.cursor)

proc selectedColony*(model: TuiModel): Option[ColonyInfo] =
  ## Get selected colony
  if model.ui.mode != ViewMode.Planets:
    return none(ColonyInfo)
  if model.ui.selectedIdx < 0 or
      model.ui.selectedIdx >= model.view.planetsRows.len:
    return none(ColonyInfo)
  let row = model.view.planetsRows[model.ui.selectedIdx]
  if row.colonyId.isNone:
    return none(ColonyInfo)
  let colonyId = row.colonyId.get()
  for colony in model.view.colonies:
    if colony.colonyId == colonyId:
      return some(colony)
  none(ColonyInfo)

proc selectedFleet*(model: TuiModel): Option[FleetInfo] =
  ## Get selected fleet
  if model.ui.mode == ViewMode.Fleets and
      model.ui.selectedIdx < model.view.fleets.len:
    some(model.view.fleets[model.ui.selectedIdx])
  else:
    none(FleetInfo)

proc ownedColonyCoords*(model: TuiModel): seq[HexCoord] =
  ## Get coordinates of all owned colonies
  result = @[]
  for sys in model.view.systems.values:
    if sys.owner.isSome and sys.owner.get == model.view.viewingHouse:
      result.add(sys.coords)

# =============================================================================
# View Mode Helpers
# =============================================================================

proc viewModeLabel*(mode: ViewMode): string =
  ## Get the display label for a view mode
  case mode
  of ViewMode.Overview: "Overview"
  of ViewMode.Planets: "Colony"
  of ViewMode.Fleets: "Fleets"
  of ViewMode.Research: "Tech"
  of ViewMode.Espionage: "Espionage"
  of ViewMode.Economy: "General"
  of ViewMode.Reports: "Reports"
  of ViewMode.Messages: "Intel"
  of ViewMode.Settings: "Settings"
  of ViewMode.PlanetDetail: "Colony"
  of ViewMode.FleetDetail: "Fleet"
  of ViewMode.ReportDetail: "Report"

proc isPrimaryView*(mode: ViewMode): bool =
  ## Check if mode is a primary view (F-keys)
  mode in {ViewMode.Overview, ViewMode.Planets, ViewMode.Fleets,
           ViewMode.Research, ViewMode.Espionage, ViewMode.Economy,
           ViewMode.Reports, ViewMode.Settings}

proc isDetailView*(mode: ViewMode): bool =
  ## Check if mode is a detail/drill-down view
  mode in {ViewMode.PlanetDetail, ViewMode.FleetDetail, ViewMode.ReportDetail}

# =============================================================================
# Breadcrumb Helpers
# =============================================================================

proc pushBreadcrumb*(model: var TuiModel, label: string, mode: ViewMode,
                     entityId: int = 0) =
  ## Push a new breadcrumb onto the navigation stack
  model.ui.breadcrumbs.add(initBreadcrumb(label, mode, entityId))

proc popBreadcrumb*(model: var TuiModel): bool =
  ## Pop the last breadcrumb, returns false if at root
  if model.ui.breadcrumbs.len > 1:
    model.ui.breadcrumbs.setLen(model.ui.breadcrumbs.len - 1)
    return true
  return false

proc resetBreadcrumbs*(model: var TuiModel, mode: ViewMode) =
  ## Reset breadcrumbs to a primary view
  model.ui.breadcrumbs = @[initBreadcrumb("Home", ViewMode.Overview)]
  if mode != ViewMode.Overview:
    model.ui.breadcrumbs.add(initBreadcrumb(mode.viewModeLabel, mode))

proc currentBreadcrumb*(model: TuiModel): BreadcrumbItem =
  ## Get the current (last) breadcrumb
  if model.ui.breadcrumbs.len > 0:
    model.ui.breadcrumbs[^1]
  else:
    initBreadcrumb("Home", ViewMode.Overview)

proc breadcrumbDepth*(model: TuiModel): int =
  ## Get breadcrumb depth
  model.ui.breadcrumbs.len

# =============================================================================
# Multi-Select Helpers (for Fleet batch operations)
# =============================================================================

proc toggleFleetSelection*(model: var TuiModel, fleetId: int) =
  ## Toggle fleet selection for batch operations
  let idx = model.ui.selectedFleetIds.find(fleetId)
  if idx >= 0:
    model.ui.selectedFleetIds.delete(idx)
  else:
    model.ui.selectedFleetIds.add(fleetId)

proc clearFleetSelection*(model: var TuiModel) =
  ## Clear all fleet selections
  model.ui.selectedFleetIds.setLen(0)

proc isFleetSelected*(model: TuiModel, fleetId: int): bool =
  ## Check if a fleet is selected
  fleetId in model.ui.selectedFleetIds

proc selectedFleetCount*(model: TuiModel): int =
  ## Get number of selected fleets
  model.ui.selectedFleetIds.len

# =============================================================================
# Expert Mode Helpers
# =============================================================================

proc clearExpertFeedback*(model: var TuiModel) =
  ## Clear expert mode feedback message
  model.ui.expertModeFeedback = ""

proc enterExpertMode*(model: var TuiModel) =
  ## Enter expert mode
  model.ui.expertModeActive = true
  model.ui.expertModeInput = ""
  model.ui.expertPaletteSelection = 0
  model.clearExpertFeedback()

proc exitExpertMode*(model: var TuiModel) =
  ## Exit expert mode
  model.ui.expertModeActive = false
  model.ui.expertModeInput = ""
  model.ui.expertPaletteSelection = -1

proc setExpertFeedback*(model: var TuiModel, message: string) =
  ## Update expert mode feedback message
  model.ui.expertModeFeedback = message

proc addToExpertHistory*(model: var TuiModel, command: string) =
  ## Add command to expert mode history
  if command.len > 0:
    model.ui.expertModeHistory.add(command)
    model.ui.expertModeHistoryIdx = model.ui.expertModeHistory.len

proc stagedCommandCount*(model: TuiModel): int =
  ## Get total number of staged commands
  model.ui.stagedFleetCommands.len +
    model.ui.stagedBuildCommands.len +
    model.ui.stagedRepairCommands.len +
    model.ui.stagedScrapCommands.len

proc stagedCommandEntries*(model: TuiModel): seq[StagedCommandEntry] =
  ## Get flattened list of staged commands in display order
  result = @[]
  for idx in 0 ..< model.ui.stagedFleetCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Fleet, index: idx))
  for idx in 0 ..< model.ui.stagedBuildCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Build, index: idx))
  for idx in 0 ..< model.ui.stagedRepairCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Repair, index: idx))
  for idx in 0 ..< model.ui.stagedScrapCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Scrap, index: idx))

proc formatFleetOrder*(cmd: FleetCommand): string =
  ## Format a fleet command for display
  result = "Fleet " & $cmd.fleetId & ": "
  let code = fleetCommandCode(cmd.commandType)
  let label = fleetCommandLabel(cmd.commandType)
  result.add(code & " " & label)
  if cmd.targetSystem.isSome:
    result.add(" -> System " & $cmd.targetSystem.get())
  if cmd.targetFleet.isSome:
    result.add(" -> Fleet " & $cmd.targetFleet.get())
  if cmd.roe.isSome:
    result.add(" (ROE " & $cmd.roe.get() & ")")

proc formatBuildOrder*(cmd: BuildCommand): string =
  ## Format a build command for display
  result = "Colony " & $cmd.colonyId & ": Build "
  case cmd.buildType
  of BuildType.Ship:
    if cmd.shipClass.isSome:
      result.add($cmd.shipClass.get())
  of BuildType.Facility:
    if cmd.facilityClass.isSome:
      result.add($cmd.facilityClass.get())
  of BuildType.Ground:
    if cmd.groundClass.isSome:
      result.add($cmd.groundClass.get())
  of BuildType.Industrial:
    result.add("Industrial Units")
  of BuildType.Infrastructure:
    result.add("Infrastructure")

  if cmd.quantity != 1:
    result.add(" x" & $cmd.quantity)

proc stagedCommandsSummary*(model: TuiModel): string =
  ## Summarize staged commands with numbered list
  let entries = model.stagedCommandEntries()
  if entries.len == 0:
    return "No commands staged"

  var lines: seq[string] = @[]
  lines.add("Staged commands (" & $entries.len & "):")
  for idx, entry in entries:
    let label =
      case entry.kind
      of StagedCommandKind.Fleet:
        formatFleetOrder(model.ui.stagedFleetCommands[entry.index])
      of StagedCommandKind.Build:
        formatBuildOrder(model.ui.stagedBuildCommands[entry.index])
      of StagedCommandKind.Repair:
        "Repair command " & $entry.index
      of StagedCommandKind.Scrap:
        "Scrap command " & $entry.index
    lines.add("  " & $(idx + 1) & ". " & label)
  lines.join(" | ")

proc dropStagedCommand*(model: var TuiModel, entry: StagedCommandEntry): bool =
  ## Remove staged command by entry
  case entry.kind
  of StagedCommandKind.Fleet:
    if entry.index < model.ui.stagedFleetCommands.len:
      model.ui.stagedFleetCommands.delete(entry.index)
      return true
  of StagedCommandKind.Build:
    if entry.index < model.ui.stagedBuildCommands.len:
      model.ui.stagedBuildCommands.delete(entry.index)
      return true
  of StagedCommandKind.Repair:
    if entry.index < model.ui.stagedRepairCommands.len:
      model.ui.stagedRepairCommands.delete(entry.index)
      return true
  of StagedCommandKind.Scrap:
    if entry.index < model.ui.stagedScrapCommands.len:
      model.ui.stagedScrapCommands.delete(entry.index)
      return true
  false

# =============================================================================
# Order Entry Helpers
# =============================================================================

proc startOrderEntry*(model: var TuiModel, fleetId: int, cmdType: int) =
  ## Begin order entry mode for a fleet
  model.ui.orderEntryActive = true
  model.ui.orderEntryFleetId = fleetId
  model.ui.orderEntryCommandType = cmdType
  model.ui.orderEntryPreviousMode = model.ui.mode
  # Switch to Overview (map) for target selection
  model.ui.mode = ViewMode.Overview
  model.ui.statusMessage =
    "Select target: [arrows] move | [Enter] confirm | [Esc] cancel"

proc cancelOrderEntry*(model: var TuiModel) =
  ## Cancel order entry and return to previous view
  model.ui.orderEntryActive = false
  model.ui.mode = model.ui.orderEntryPreviousMode
  model.ui.mapState.selected = none(HexCoord)
  model.ui.statusMessage = "Order cancelled"

proc confirmOrderEntry*(model: var TuiModel, targetSystemId: int) =
  ## Confirm order entry and queue the order for writing
  model.ui.pendingFleetOrderFleetId = model.ui.orderEntryFleetId
  model.ui.pendingFleetOrderCommandType = model.ui.orderEntryCommandType
  model.ui.pendingFleetOrderTargetSystemId = targetSystemId
  model.ui.pendingFleetOrderReady = true
  model.ui.orderEntryActive = false
  model.ui.mode = model.ui.orderEntryPreviousMode
  model.ui.mapState.selected = none(HexCoord)

proc queueImmediateOrder*(model: var TuiModel, fleetId: int, cmdType: int) =
  ## Queue an immediate order (no target needed, like Hold)
  model.ui.pendingFleetOrderFleetId = fleetId
  model.ui.pendingFleetOrderCommandType = cmdType
  model.ui.pendingFleetOrderTargetSystemId = 0
  model.ui.pendingFleetOrderReady = true

proc clearPendingOrder*(model: var TuiModel) =
  ## Clear the pending order after it's been processed
  model.ui.pendingFleetOrderReady = false
  model.ui.pendingFleetOrderFleetId = 0
  model.ui.pendingFleetOrderCommandType = 0
  model.ui.pendingFleetOrderTargetSystemId = 0

proc orderEntryNeedsTarget*(cmdType: int): bool =
  ## Check if a command type needs target selection
  cmdType in [CmdMove, CmdPatrol, CmdBlockade, CmdBombard, CmdInvade,
              CmdBlitz, CmdColonize, CmdScoutColony, CmdScoutSystem,
              CmdJoinFleet, CmdRendezvous]

# =============================================================================
# Command Packet Builder
# =============================================================================

proc buildCommandPacket*(model: TuiModel, turn: int32,
                         houseId: HouseId): CommandPacket =
  ## Build CommandPacket from staged commands
  ## Used by main loop to submit turn to engine/Nostr
  
  CommandPacket(
    houseId: houseId,
    turn: turn,
    fleetCommands: model.ui.stagedFleetCommands,
    buildCommands: model.ui.stagedBuildCommands,
    repairCommands: model.ui.stagedRepairCommands,
    scrapCommands: model.ui.stagedScrapCommands,
    # Empty/default values for other command types (Phase 2+)
    researchAllocation: ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    ),
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    espionageActions: @[],
    ebpInvestment: 0,
    cipInvestment: 0
  )
