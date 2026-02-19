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
##   F4 Tech       - PP allocation -> ERP/SRP/TRP progress
##   F5 Espionage  - EBP/CIP budget, intel operations
##   F6 General    - Diplomacy, tax, empire policy
##   F7 (unused)   - Reserved
##   F8 Settings   - Display options, automation defaults
##   Ctrl+N Inbox  - Player messages + turn reports

import std/[options, tables, algorithm, strutils, sequtils, sets, heapqueue]
import ../tui/widget/scroll_state
import ../tui/widget/entry_modal
import ../tui/hex_labels
import ../state/identity
import ../tui/widget/text_input
import ../../common/message_types
import ../../engine/globals
import ../../engine/types/[core, colony, fleet, production, command, tech,
  ship, combat, facilities, ground_unit, zero_turn, espionage]
import ../../engine/systems/espionage/engine

export entry_modal
export identity
export zero_turn

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
  FleetDetailInfoHeight* = 3
  FleetDetailSeparatorHeight* = 1
  FleetDetailShipsHeaderHeight* = 0
  FleetDetailFooterHeight* = 2
  FleetDetailTableBaseHeight* = 4

proc commandLabel*(cmdNum: int): string =
  ## Get human-readable label for fleet command (matches spec 6.3.1)
  case cmdNum
  of CmdHold: "Hold"
  of CmdMove: "Move"
  of CmdSeekHome: "Seek Home"
  of CmdPatrol: "Patrol"
  of CmdGuardStarbase: "Guard Starbase"
  of CmdGuardColony: "Guard Colony"
  of CmdBlockade: "Blockade"
  of CmdBombard: "Bombard"
  of CmdInvade: "Invade"
  of CmdBlitz: "Blitz"
  of CmdColonize: "Colonize"
  of CmdScoutColony: "Scout Colony"
  of CmdScoutSystem: "Scout System"
  of CmdHackStarbase: "Hack Starbase"
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

proc commandRequirements*(cmdType: FleetCommandType): string =
  ## Get human-readable requirements text (matches spec 6.3.1)
  case cmdType
  of FleetCommandType.Hold: "None"
  of FleetCommandType.Move: "None"
  of FleetCommandType.SeekHome: "None"
  of FleetCommandType.Patrol: "None"
  of FleetCommandType.GuardStarbase: "Combat ship(s)"
  of FleetCommandType.GuardColony: "Combat ship(s)"
  of FleetCommandType.Blockade: "Combat ship(s)"
  of FleetCommandType.Bombard: "Combat ship(s)"
  of FleetCommandType.Invade: "Combat ship(s) & loaded Transports"
  of FleetCommandType.Blitz: "Loaded Troop Transports"
  of FleetCommandType.Colonize: "One ETAC"
  of FleetCommandType.ScoutColony: "Scout-only fleet (1+ scouts)"
  of FleetCommandType.ScoutSystem: "Scout-only fleet (1+ scouts)"
  of FleetCommandType.HackStarbase: "Scout-only fleet (1+ scouts)"
  of FleetCommandType.JoinFleet: "None"
  of FleetCommandType.Rendezvous: "None"
  of FleetCommandType.Salvage: "Friendly colony system"
  of FleetCommandType.Reserve: "At friendly colony"
  of FleetCommandType.Mothball: "At friendly colony w/ Spaceport"
  of FleetCommandType.View: "Any ship type"

proc allFleetCommands*(): seq[FleetCommandType] =
  ## Get all fleet commands in order (00-19)
  @[
    FleetCommandType.Hold,        # 00
    FleetCommandType.Move,        # 01
    FleetCommandType.SeekHome,    # 02
    FleetCommandType.Patrol,      # 03
    FleetCommandType.GuardStarbase, # 04
    FleetCommandType.GuardColony, # 05
    FleetCommandType.Blockade,    # 06
    FleetCommandType.Bombard,     # 07
    FleetCommandType.Invade,      # 08
    FleetCommandType.Blitz,       # 09
    FleetCommandType.Colonize,    # 10
    FleetCommandType.ScoutColony, # 11
    FleetCommandType.ScoutSystem, # 12
    FleetCommandType.HackStarbase, # 13
    FleetCommandType.JoinFleet,   # 14
    FleetCommandType.Rendezvous,  # 15
    FleetCommandType.Salvage,     # 16
    FleetCommandType.Reserve,     # 17
    FleetCommandType.Mothball,    # 18
    FleetCommandType.View         # 19
  ]

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

  BuildRowKey* = object
    kind*: BuildOptionKind
    shipClass*: Option[ShipClass]
    facilityClass*: Option[FacilityClass]
    groundClass*: Option[GroundClass]

  DockSummary* = object
    constructionAvailable*: int
    constructionTotal*: int
    repairAvailable*: int
    repairTotal*: int

  ColonyLimitSnapshot* = object
    industrialUnits*: int
    fighters*: int
    spaceports*: int
    starbases*: int
    shields*: int

  BuildCategory* {.pure.} = enum
    Ships, Facilities, Ground

  BuildModalFocus* {.pure.} = enum
    CategoryTabs, BuildList, QueueList

  BuildModalState* = object
    active*: bool
    colonyId*: int
    colonyName*: string
    category*: BuildCategory
    focus*: BuildModalFocus
    selectedBuildIdx*: int
    selectedQueueIdx*: int
    availableOptions*: seq[BuildOption]
    dockSummary*: DockSummary
    ppAvailable*: int
    cstLevel*: int
    stagedBuildCommands*: seq[BuildCommand]
    buildListScroll*: ScrollState
    queueScroll*: ScrollState

  QueueModalState* = object
    active*: bool
    colonyId*: int
    colonyName*: string
    selectedIdx*: int
    stagedBuildCommands*: seq[BuildCommand]
    scroll*: ScrollState

  FleetConsoleSystem* = object
    ## System with fleets for fleet console (cached from PlayerState)
    systemId*: int
    systemName*: string
    sectorLabel*: string
    fleetCount*: int

  FleetConsoleFleet* = object
    ## Fleet info for console list (cached from PlayerState)
    fleetId*: int
    name*: string            ## Per-house label (e.g. "A1", "B3")
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
    needsAttention*: bool

  SystemPickerEntry* = object
    ## System entry for target selection picker
    systemId*: int
    name*: string
    coordLabel*: string      ## Ring+position label ("H", "A1", "B3")

  SystemPickerFilterResult* = object
    systems*: seq[SystemPickerEntry]
    emptyMessage*: string

  FleetSubModal* {.pure.} = enum
    ## Sub-modal states for fleet detail modal
    None
    CommandPicker
    ROEPicker
    ConfirmPrompt
    NoticePrompt
    SystemPicker      # Target system selection table (for Move, Patrol, etc.)
    FleetPicker       # Select target fleet (for JoinFleet command)
    Staged            # Terminal state: command staged successfully
    ZTCPicker         # Zero-Turn Command picker (1-9)
    ShipSelector      # Ship checkbox list (for Detach/Transfer ZTCs) - placeholder
    CargoParams       # Cargo parameter entry (for Load/Unload Cargo) - placeholder
    FighterParams     # Fighter parameter entry (for Load/Unload/Transfer Fighters) - placeholder

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
    commandCategory*: CommandCategory  # DEPRECATED: now using flat list
    commandIdx*: int           # Index in flat command list (0-19)
    commandPickerCommands*: seq[FleetCommandType]
    roeValue*: int             # 0-10
    confirmPending*: bool
    confirmMessage*: string
    pendingCommandType*: FleetCommandType  # For confirmation flow
    noticeMessage*: string
    noticeReturnSubModal*: FleetSubModal
    shipScroll*: ScrollState
    commandDigitBuffer*: string  # Buffer for two-digit quick entry (e.g., "0", "07")
    commandDigitTime*: float     # Time when first digit was entered (for timeout)
    shipCount*: int
    # FleetPicker state (for JoinFleet target selection)
    fleetPickerIdx*: int       # Selected fleet index in picker
    fleetPickerScroll*: ScrollState  # Scroll state for fleet picker list
    fleetPickerCandidates*: seq[FleetConsoleFleet]  # Other fleets at same system
    # ZTCPicker state (for Zero-Turn Commands)
    ztcIdx*: int               # Selected ZTC index in filtered picker list
    ztcDigitBuffer*: string    # Single-digit quick select buffer (1-9)
    ztcPickerCommands*: seq[ZeroTurnCommandType]
    ztcType*: Option[ZeroTurnCommandType]
    ztcTargetFleetId*: int
    shipSelectorIdx*: int
    shipSelectorShipIds*: seq[ShipId]
    shipSelectorSelected*: HashSet[ShipId]
    cargoType*: CargoClass
    cargoQuantityInput*: TextInputState
    fighterQuantityInput*: TextInputState
    # SystemPicker state (for target system selection)
    systemPickerIdx*: int      # Selected system index
    systemPickerSystems*: seq[SystemPickerEntry]  # Sorted system list
    systemPickerFilter*: string  # Typed coordinate filter
    systemPickerFilterTime*: float  # Filter timeout
    systemPickerCommandType*: FleetCommandType  # Command being targeted
    # Direct sub-modal tracking: when true, Esc from the top-level sub-modal
    # closes the entire FleetDetail modal (because it was opened directly into
    # a sub-modal via C/R/Z from the fleet list, not via Enter→detail view)
    directSubModal*: bool

  FleetListSort* {.pure.} = enum
    Flag
    FleetId
    Location
    Sector
    Ships
    AttackStrength
    DefenseStrength
    Command
    Destination
    ETA
    ROE
    Status

  TableSortState* = object
    ## Reusable sort state for any table view.
    ## Column index is 0-based, matching column order.
    columnIdx*: int
    ascending*: bool
    columnCount*: int

  FleetListState* = object
    sortState*: TableSortState
    searchActive*: bool
    searchQuery*: string
    jumpBuffer*: string
    jumpTime*: float

  InboxSection* {.pure.} = enum
    ## Which section the inbox cursor is in
    Messages
    Reports

  InboxPaneFocus* {.pure.} = enum
    ## Which pane has focus in the inbox
    List          ## Left panel (houses + turn buckets)
    Detail        ## Right panel (conversation or report)
    Compose       ## Compose input (messages only)

  ViewMode* {.pure.} = enum
    ## Current UI view (maps to primary view number)
    ##
    ## Primary views:
    Overview = 1      ## Strategic dashboard
    Planets = 2       ## Colony management
    Fleets = 3        ## Fleet console
    Research = 4      ## Tech & research
    Espionage = 5     ## Intel operations
    Economy = 6       ## General (tax/diplomacy)
    IntelDb = 8       ## Intel database (Starmap)
    Settings = 9      ## Game settings
    Messages = 10     ## Player messages
    # Sub-views (not directly accessible via primary hotkeys)
    PlanetDetail = 20 ## Planet detail (Summary/Economy/Construction/etc.)
    FleetDetail = 30  ## Fleet detail view
    IntelDetail = 80  ## Intel system detail view

# Legacy aliases for backward compatibility
const
  Colonies* = ViewMode.Planets    ## Legacy alias for Planets
  Map* = ViewMode.Overview        ## Legacy: Map mode (now part of Overview)
  Orders* = ViewMode.Fleets       ## Legacy: Orders (now part of Fleets)
  Systems* = ViewMode.Overview    ## Legacy: Systems (now part of Overview)

type
  StagedCommandKind* {.pure.} = enum
    Fleet
    ZeroTurn
    Build
    Repair
    Scrap
    ColonyManagement
    EspionageBudget
    EspionageAction

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
    autoRepair*: bool
    autoLoadMarines*: bool
    autoLoadFighters*: bool
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
    starbaseCount*: Option[int]

  FleetInfo* = object
    ## Fleet info for list display
    id*: int
    name*: string            ## Per-house label (e.g. "A1", "B3")
    location*: int          ## System ID
    locationName*: string
    sectorLabel*: string
    shipCount*: int
    owner*: int
    command*: int           ## Fleet command (0-19, see 06-operations.md)
    commandLabel*: string   ## Human-readable command ("Hold", "Move", "Patrol")
    isIdle*: bool           ## True if command is Hold (00)
    roe*: int               ## Rules of Engagement (0-10)
    attackStrength*: int
    defenseStrength*: int
    statusLabel*: string    ## Active/Reserve/Mothballed
    destinationLabel*: string
    destinationSystemId*: int
    eta*: int
    hasCrippled*: bool
    hasCombatShips*: bool
    hasSupportShips*: bool
    hasScouts*: bool
    hasTroopTransports*: bool
    hasEtacs*: bool
    isScoutOnly*: bool       ## All non-destroyed ships are Scouts
    seekHomeTarget*: Option[int] ## Precomputed SeekHome target system
    needsAttention*: bool

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

  FleetViewMode* {.pure.} = enum
    ## Fleet console sub-modes
    SystemView    ## Grouped by location
    ListView      ## Flat list with multi-select

  EspionageFocus* {.pure.} = enum
    Budget
    Targets
    Operations

  EspionageBudgetChannel* {.pure.} = enum
    Ebp
    Cip

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

  InboxItemKind* {.pure.} = enum
    ## Kind tag for flat inbox list items
    SectionHeader   ## Non-selectable section label
    MessageHouse    ## A house in the Messages section
    TurnBucket      ## A turn bucket in the Reports section

  InboxItem* = object
    ## One row in the flat inbox list
    kind*: InboxItemKind
    label*: string
    houseIdx*: int      ## Index into messageHouses (if MessageHouse)
    turnIdx*: int       ## Index into turnBuckets (if TurnBucket)
    unread*: int        ## Unread count badge

  ResearchItemKind* {.pure.} = enum
    EconomicLevel
    ScienceLevel
    Technology

  ResearchItem* = object
    category*: string
    code*: string
    name*: string
    kind*: ResearchItemKind
    field*: TechField

const ResearchItems* = [
  ResearchItem(
    category: "FOUNDATIONS",
    code: "SL",
    name: "Science Level",
    kind: ResearchItemKind.ScienceLevel,
    field: TechField.WeaponsTech
  ),
  ResearchItem(
    category: "FOUNDATIONS",
    code: "EL",
    name: "Economic Level",
    kind: ResearchItemKind.EconomicLevel,
    field: TechField.WeaponsTech
  ),
  ResearchItem(
    category: "MILITARY",
    code: "WEP",
    name: "Weapons Tech",
    kind: ResearchItemKind.Technology,
    field: TechField.WeaponsTech
  ),
  ResearchItem(
    category: "MILITARY",
    code: "CST",
    name: "Construction",
    kind: ResearchItemKind.Technology,
    field: TechField.ConstructionTech
  ),
  ResearchItem(
    category: "MILITARY",
    code: "FC",
    name: "Fleet Command",
    kind: ResearchItemKind.Technology,
    field: TechField.FlagshipCommandTech
  ),
  ResearchItem(
    category: "MILITARY",
    code: "SC",
    name: "Strategic Cmd",
    kind: ResearchItemKind.Technology,
    field: TechField.StrategicCommandTech
  ),
  ResearchItem(
    category: "MILITARY",
    code: "FD",
    name: "Fighter Doc",
    kind: ResearchItemKind.Technology,
    field: TechField.FighterDoctrine
  ),
  ResearchItem(
    category: "MILITARY",
    code: "ACO",
    name: "Carrier Ops",
    kind: ResearchItemKind.Technology,
    field: TechField.AdvancedCarrierOps
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "SLD",
    name: "Shields",
    kind: ResearchItemKind.Technology,
    field: TechField.ShieldTech
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "CLK",
    name: "Cloaking",
    kind: ResearchItemKind.Technology,
    field: TechField.CloakingTech
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "ELI",
    name: "Electronic Int",
    kind: ResearchItemKind.Technology,
    field: TechField.ElectronicIntelligence
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "TER",
    name: "Terraforming",
    kind: ResearchItemKind.Technology,
    field: TechField.TerraformingTech
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "STL",
    name: "Strategic Lift",
    kind: ResearchItemKind.Technology,
    field: TechField.StrategicLiftTech
  ),
  ResearchItem(
    category: "SCIENCE",
    code: "CIC",
    name: "Counter Intel",
    kind: ResearchItemKind.Technology,
    field: TechField.CounterIntelligence
  )
]

proc researchItems*(): seq[ResearchItem] =
  @ResearchItems

proc researchSelectableCount*(): int =
  ResearchItems.len

proc researchItemAt*(idx: int): ResearchItem =
  let clamped = clamp(idx, 0, max(0, ResearchItems.len - 1))
  ResearchItems[clamped]

proc researchIndexForCode*(code: string): int =
  for idx, item in ResearchItems:
    if item.code == code:
      return idx
  0

proc espionageActions*(): seq[EspionageAction] =
  result = @[]
  for action in EspionageAction:
    result.add(action)

proc espionageActionLabel*(action: EspionageAction): string =
  case action
  of EspionageAction.TechTheft: "Tech Theft"
  of EspionageAction.SabotageLow: "Low Impact Sabotage"
  of EspionageAction.SabotageHigh: "High Impact Sabotage"
  of EspionageAction.Assassination: "Assassination"
  of EspionageAction.CyberAttack: "Cyber Attack"
  of EspionageAction.EconomicManipulation: "Economic Manipulation"
  of EspionageAction.PsyopsCampaign: "Psyops Campaign"
  of EspionageAction.CounterIntelSweep: "Counter-Intel Sweep"
  of EspionageAction.IntelTheft: "Intel Theft"
  of EspionageAction.PlantDisinformation: "Plant Disinformation"

proc espionageActionCost*(action: EspionageAction): int =
  actionCost(action)

proc espionageActionDesc*(action: EspionageAction): string =
  case action
  of EspionageAction.TechTheft:
    "Steal research"
  of EspionageAction.SabotageLow:
    "Minor disruption"
  of EspionageAction.SabotageHigh:
    "Major disruption"
  of EspionageAction.Assassination:
    "Remove leader"
  of EspionageAction.CyberAttack:
    "Disrupt systems"
  of EspionageAction.EconomicManipulation:
    "Distort markets"
  of EspionageAction.PsyopsCampaign:
    "Influence morale"
  of EspionageAction.CounterIntelSweep:
    "Expose agents"
  of EspionageAction.IntelTheft:
    "Steal intel"
  of EspionageAction.PlantDisinformation:
    "Seed false intel"

# ============================================================================
# UI State (interaction + transient)
# ============================================================================

type
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
    lobbyProfilePubkeyInput*: TextInputState
    lobbyProfileNameInput*: TextInputState
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
    fleetViewMode*: FleetViewMode
    selectedFleetIds*: seq[int]
    selectedColonyId*: int
    selectedFleetId*: int
    intelDetailSystemId*: int
    intelDetailFleetPopupActive*: bool
    intelDetailFleetSelectedIdx*: int
    intelDetailFleetScrollOffset*: int
    intelDetailFleetCount*: int
    intelDetailNoteScrollOffset*: int
    intelNoteEditActive*: bool
    intelNoteEditor*: TextInputState
    intelNoteSaveRequested*: bool
    intelNoteSaveSystemId*: int
    intelNoteSaveText*: string

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

    # Fleet list state (ListView mode)
    fleetListState*: FleetListState

    # Intel DB jump state
    intelJumpBuffer*: string
    intelJumpTime*: float

    # Planets/Colony jump state
    planetsJumpBuffer*: string
    planetsJumpTime*: float

    # Expert mode state
    expertModeActive*: bool
    expertModeInput*: TextInputState
    expertModeHistory*: seq[string]
    expertModeHistoryIdx*: int
    expertModeFeedback*: string
    expertPaletteSelection*: int

    # Staged commands (for turn submission)
    stagedFleetCommands*: Table[int, FleetCommand]
    stagedZeroTurnCommands*: seq[ZeroTurnCommand]
    stagedBuildCommands*: seq[BuildCommand]
    stagedRepairCommands*: seq[RepairCommand]
    stagedScrapCommands*: seq[ScrapCommand]
    stagedColonyManagement*: seq[ColonyManagementCommand]
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
    showHelpOverlay*: bool

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
    intelScroll*: ScrollState
    messagesScroll*: ScrollState
    settingsScroll*: ScrollState

    # Research state
    researchAllocation*: ResearchAllocation
    researchDigitBuffer*: string
    researchDigitTime*: float

    # Espionage state
    espionageFocus*: EspionageFocus
    espionageBudgetChannel*: EspionageBudgetChannel
    espionageTargetIdx*: int
    espionageOperationIdx*: int
    stagedEbpInvestment*: int32
    stagedCipInvestment*: int32
    stagedEspionageActions*: seq[EspionageAttempt]

    # Inbox state (unified messages + reports)
    inboxFocus*: InboxPaneFocus
    inboxSection*: InboxSection
    inboxListIdx*: int            ## Flat index in unified list
    messageHouseIdx*: int         ## Selected house within Messages
    inboxTurnIdx*: int            ## Selected turn bucket in Reports
    inboxReportIdx*: int          ## Selected report within turn
    inboxTurnExpanded*: bool      ## Whether turn bucket is expanded
    messageComposeActive*: bool
    messageComposeInput*: TextInputState
    inboxDetailScroll*: ScrollState

    # Entry modal state (replaces legacy lobby UI)
    entryModal*: EntryModalState

    # Build modal state
    buildModal*: BuildModalState
    # Queue modal state
    queueModal*: QueueModalState

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
    espionageEbpPool*: Option[int]
    espionageCipPool*: Option[int]
    prestige*: int
    prestigeRank*: int
    totalHouses*: int
    production*: int
    houseTaxRate*: int
    commandUsed*: int
    commandMax*: int
    planetBreakersInFleets*: int
    alertCount*: int
    unreadMessages*: int
    techLevels*: Option[TechLevel]
    researchPoints*: Option[ResearchPoints]

    # Collections for display
    houseNames*: Table[int, string]
    systems*: Table[HexCoord, SystemInfo]
    colonies*: seq[ColonyInfo]
    planetsRows*: seq[PlanetRow]
    intelRows*: seq[IntelRow]
    fleets*: seq[FleetInfo]
    commands*: seq[CommandInfo]
    reports*: seq[ReportEntry]
    turnBuckets*: seq[TurnBucket]
    inboxItems*: seq[InboxItem]
    messageThreads*: Table[int32, seq[GameMessage]]
    messageHouses*: seq[tuple[id: int32, name: string, unread: int]]

    maxRing*: int
    homeworld*: Option[HexCoord]

    # Lobby data lists
    lobbyActiveGames*: seq[ActiveGameInfo]
    lobbyJoinGames*: seq[JoinGameInfo]

    # Starmap lane data for client-side ETA
    laneTypes*: Table[(int, int), int]
    laneNeighbors*: Table[int, seq[int]]
    ownedSystemIds*: HashSet[int]
    knownEnemyColonySystemIds*: HashSet[int]
    systemCoords*: Table[int, HexCoord]
    colonyLimits*: Table[int, ColonyLimitSnapshot]
    ownColoniesBySystem*: Table[int, Colony]
    ownFleetsById*: Table[int, Fleet]
    ownShipsById*: Table[int, Ship]

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

proc buildTurnBuckets*(
    reports: seq[ReportEntry]): seq[TurnBucket] =
  ## Group reports by turn, sorted newest-first
  var bucketMap: Table[int, seq[ReportEntry]]
  for r in reports:
    if r.turn notin bucketMap:
      bucketMap[r.turn] = @[]
    bucketMap[r.turn].add(r)
  var turns: seq[int] = @[]
  for t in bucketMap.keys:
    turns.add(t)
  turns.sort(SortOrder.Descending)
  result = @[]
  for t in turns:
    var unread = 0
    for r in bucketMap[t]:
      if r.isUnread: inc unread
    result.add(TurnBucket(
      turn: t,
      unreadCount: unread,
      reports: bucketMap[t]
    ))

proc buildInboxItems*(
    houses: seq[tuple[id: int32, name: string, unread: int]],
    buckets: seq[TurnBucket]): seq[InboxItem] =
  ## Build the flat inbox list from messages + reports
  result = @[]
  # Messages section
  result.add(InboxItem(
    kind: InboxItemKind.SectionHeader,
    label: "MESSAGES",
    houseIdx: -1, turnIdx: -1, unread: 0))
  for i, h in houses:
    result.add(InboxItem(
      kind: InboxItemKind.MessageHouse,
      label: h.name,
      houseIdx: i, turnIdx: -1, unread: h.unread))
  # Reports section
  result.add(InboxItem(
    kind: InboxItemKind.SectionHeader,
    label: "REPORTS",
    houseIdx: -1, turnIdx: -1, unread: 0))
  for i, b in buckets:
    let lbl = "Turn " & $b.turn
    result.add(InboxItem(
      kind: InboxItemKind.TurnBucket,
      label: lbl,
      houseIdx: -1, turnIdx: i, unread: b.unreadCount))

proc firstSelectableIdx*(
    items: seq[InboxItem]): int =
  ## Return index of first selectable item, or 0
  for i, item in items:
    if item.kind != InboxItemKind.SectionHeader:
      return i
  0

proc nextSelectableIdx*(
    items: seq[InboxItem], current: int,
    delta: int): int =
  ## Move to next/prev selectable item, skipping headers
  var idx = current + delta
  while idx >= 0 and idx < items.len:
    if items[idx].kind != InboxItemKind.SectionHeader:
      return idx
    idx += delta
  current  # Stay put if nothing selectable found

proc initBreadcrumb*(label: string, mode: ViewMode,
                     entityId: int = 0): BreadcrumbItem =
  ## Create a breadcrumb item
  BreadcrumbItem(label: label, viewMode: mode, entityId: entityId)

proc initTableSortState*(columnCount: int): TableSortState =
  ## Create initial sort state (first column, ascending)
  TableSortState(
    columnIdx: 0, ascending: true,
    columnCount: columnCount)

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
    lobbyProfilePubkeyInput: initTextInputState(maxDisplayWidth = 64),
    lobbyProfileNameInput: initTextInputState(maxDisplayWidth = 32),
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
    fleetViewMode: FleetViewMode.ListView,
    selectedFleetIds: @[],
    selectedColonyId: 0,
    selectedFleetId: 0,
    intelDetailSystemId: 0,
    intelDetailFleetPopupActive: false,
    intelDetailFleetSelectedIdx: 0,
    intelDetailFleetScrollOffset: 0,
    intelDetailFleetCount: 0,
    intelDetailNoteScrollOffset: 0,
    intelNoteEditActive: false,
    intelNoteEditor: initTextInputState(
      mode = EditorMode.MultiLine),
    intelNoteSaveRequested: false,
    intelNoteSaveSystemId: 0,
    intelNoteSaveText: "",
    fleetConsoleFocus: FleetConsoleFocus.SystemsPane,
    fleetConsoleSystemIdx: 0,
    fleetConsoleFleetIdx: 0,
    fleetConsoleShipIdx: 0,
    fleetConsoleSystemScroll: initScrollState(),
    fleetConsoleFleetScroll: initScrollState(),
    fleetConsoleShipScroll: initScrollState(),
    fleetConsoleSystems: @[],
    fleetConsoleFleetsBySystem: initTable[int, seq[FleetConsoleFleet]](),
    fleetListState: FleetListState(
      sortState: initTableSortState(12),
      searchActive: false,
      searchQuery: "",
      jumpBuffer: "",
      jumpTime: 0.0
    ),
    intelJumpBuffer: "",
    intelJumpTime: 0.0,
    planetsJumpBuffer: "",
    planetsJumpTime: 0.0,
    expertModeActive: false,
    expertModeInput: initTextInputState(),
    expertModeHistory: @[],
    expertModeHistoryIdx: 0,
    expertModeFeedback: "",
    expertPaletteSelection: -1,
    stagedFleetCommands: initTable[int, FleetCommand](),
    stagedZeroTurnCommands: @[],
    stagedBuildCommands: @[],
    stagedRepairCommands: @[],
    stagedScrapCommands: @[],
    stagedColonyManagement: @[],
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
    showHelpOverlay: false,
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
    intelScroll: initScrollState(),
    messagesScroll: initScrollState(),
    settingsScroll: initScrollState(),
    researchAllocation: ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    ),
    researchDigitBuffer: "",
    researchDigitTime: 0.0,
    espionageFocus: EspionageFocus.Budget,
    espionageBudgetChannel: EspionageBudgetChannel.Ebp,
    espionageTargetIdx: 0,
    espionageOperationIdx: 0,
    stagedEbpInvestment: 0,
    stagedCipInvestment: 0,
    stagedEspionageActions: @[],
    inboxFocus: InboxPaneFocus.List,
    inboxSection: InboxSection.Messages,
    inboxListIdx: 0,
    messageHouseIdx: 0,
    inboxTurnIdx: 0,
    inboxReportIdx: 0,
    inboxTurnExpanded: false,
    messageComposeActive: false,
    messageComposeInput: initTextInputState(
      maxLength = 0, maxDisplayWidth = 0),
    inboxDetailScroll: initScrollState(),
    entryModal: newEntryModalState(),
    buildModal: BuildModalState(
      active: false,
      colonyId: 0,
      colonyName: "",
      category: BuildCategory.Ships,
      focus: BuildModalFocus.BuildList,
      selectedBuildIdx: 0,
      selectedQueueIdx: 0,
      availableOptions: @[],
      ppAvailable: -1,
      cstLevel: 1,
      stagedBuildCommands: @[],
      buildListScroll: initScrollState(),
      queueScroll: initScrollState()
    ),
    queueModal: QueueModalState(
      active: false,
      colonyId: 0,
      colonyName: "",
      selectedIdx: 0,
      stagedBuildCommands: @[],
      scroll: initScrollState()
    ),
    fleetDetailModal: FleetDetailModalState(
      active: false,
      fleetId: 0,
      subModal: FleetSubModal.None,
      commandCategory: CommandCategory.Movement,
      commandIdx: 0,
      commandPickerCommands: allFleetCommands(),
      roeValue: 6,  # Standard ROE
      confirmPending: false,
      confirmMessage: "",
      pendingCommandType: FleetCommandType.Hold,
      noticeMessage: "",
      noticeReturnSubModal: FleetSubModal.None,
      shipScroll: initScrollState(),
      shipCount: 0,
      fleetPickerIdx: 0,
      fleetPickerScroll: initScrollState(),
      fleetPickerCandidates: @[],
      ztcIdx: 0,
      ztcDigitBuffer: "",
      ztcPickerCommands: @[],
      ztcType: none(ZeroTurnCommandType),
      ztcTargetFleetId: 0,
      shipSelectorIdx: 0,
      shipSelectorShipIds: @[],
      shipSelectorSelected: initHashSet[ShipId](),
      cargoType: CargoClass.Marines,
      cargoQuantityInput: initTextInputState(),
      fighterQuantityInput: initTextInputState(),
      directSubModal: false
    )
  )

proc initTuiViewState*(): TuiViewState =
  ## Create initial view state with defaults
  result = TuiViewState(
    playerStateLoaded: false,
    turn: 1,
    viewingHouse: 1,
    houseName: "Unknown",
    treasury: 0,
    espionageEbpPool: none(int),
    espionageCipPool: none(int),
    prestige: 0,
    prestigeRank: 0,
    totalHouses: 0,
    production: 0,
    houseTaxRate: 0,
    commandUsed: 0,
    commandMax: 0,
    planetBreakersInFleets: 0,
    alertCount: 0,
    unreadMessages: 0,
    techLevels: none(TechLevel),
    researchPoints: none(ResearchPoints),
    houseNames: initTable[int, string](),
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
    turnBuckets: @[],  # Built from reports below
    messageThreads: initTable[int32, seq[GameMessage]](),
    messageHouses: @[],
    maxRing: 3,
    homeworld: none(HexCoord),
    lobbyActiveGames: @[],
    lobbyJoinGames: @[],
    laneTypes: initTable[(int, int), int](),
    laneNeighbors: initTable[int, seq[int]](),
    ownedSystemIds: initHashSet[int](),
    knownEnemyColonySystemIds: initHashSet[int](),
    systemCoords: initTable[int, HexCoord](),
    colonyLimits: initTable[int, ColonyLimitSnapshot](),
    ownColoniesBySystem: initTable[int, Colony](),
    ownFleetsById: initTable[int, Fleet](),
    ownShipsById: initTable[int, Ship](),
  )
  result.turnBuckets = buildTurnBuckets(result.reports)
  result.inboxItems = buildInboxItems(
    result.messageHouses, result.turnBuckets)

proc initTuiModel*(): TuiModel =
  ## Create initial TUI model with defaults
  TuiModel(
    ui: initTuiUiState(),
    view: initTuiViewState()
  )

proc espionageTargetHouses*(
    model: TuiModel
): seq[tuple[id: int, name: string]] =
  result = @[]
  for id, name in model.view.houseNames.pairs:
    if id <= 0:
      continue
    if id == model.view.viewingHouse:
      continue
    result.add((id: id, name: name))
  result.sort(proc(a, b: tuple[id: int, name: string]): int =
    cmp(a.id, b.id))

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

proc filteredFleets*(model: TuiModel): seq[FleetInfo]

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
  of ViewMode.Fleets:
    if model.ui.fleetViewMode == FleetViewMode.ListView:
      model.filteredFleets().len
    else:
      model.view.fleets.len
  of ViewMode.Research: researchSelectableCount()
  of ViewMode.Espionage: 0  # Espionage operations list (TODO)
  of ViewMode.Economy: 0   # Economy has no list
  of ViewMode.IntelDb: model.view.intelRows.len
  of ViewMode.Settings: 0  # TODO: settings list
  of ViewMode.Messages: model.view.inboxItems.len
  of ViewMode.PlanetDetail: 0
  of ViewMode.FleetDetail: 0
  of ViewMode.IntelDetail: 0

proc idleFleetsCount*(model: TuiModel): int =
  ## Count fleets with Hold command (awaiting orders)
  result = 0
  for fleet in model.view.fleets:
    if fleet.isIdle:
      result.inc

proc fleetMatchesSearch*(fleet: FleetInfo, query: string): bool =
  ## Match fleet against search query (fleet name or sector coords)
  if query.len == 0:
    return true
  let q = query.strip().toUpperAscii()
  if q.len == 0:
    return true
  if fleet.name.toUpperAscii() == q:
    return true
  fleet.sectorLabel.toUpperAscii().contains(q)

proc compareFleetSort(a, b: FleetInfo, sort: FleetListSort): int =
  ## Compare fleets for sorting
  case sort
  of FleetListSort.Flag:
    cmp(a.needsAttention, b.needsAttention)
  of FleetListSort.FleetId:
    cmp(a.name, b.name)
  of FleetListSort.Location:
    cmp(a.locationName, b.locationName)
  of FleetListSort.Sector:
    cmp(a.sectorLabel, b.sectorLabel)
  of FleetListSort.Ships:
    cmp(a.shipCount, b.shipCount)
  of FleetListSort.AttackStrength:
    cmp(a.attackStrength, b.attackStrength)
  of FleetListSort.DefenseStrength:
    cmp(a.defenseStrength, b.defenseStrength)
  of FleetListSort.Command:
    cmp(a.commandLabel, b.commandLabel)
  of FleetListSort.Destination:
    cmp(a.destinationLabel, b.destinationLabel)
  of FleetListSort.ETA:
    cmp(a.eta, b.eta)
  of FleetListSort.ROE:
    cmp(a.roe, b.roe)
  of FleetListSort.Status:
    cmp(a.statusLabel, b.statusLabel)

proc filteredFleets*(model: TuiModel): seq[FleetInfo] =
  ## Sort fleet list for ListView (with optional search)
  let state = model.ui.fleetListState
  result = @[]
  for fleet in model.view.fleets:
    if not fleetMatchesSearch(fleet, state.searchQuery):
      continue
    result.add(fleet)
  let ascending = state.sortState.ascending
  let sortMode = FleetListSort(state.sortState.columnIdx)
  result.sort(proc(a, b: FleetInfo): int =
    let cmpResult = compareFleetSort(a, b, sortMode)
    if cmpResult == 0:
      cmp(a.name, b.name)
    elif ascending:
      cmpResult
    else:
      -cmpResult
  )

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

proc colonyInfoById*(model: TuiModel, colonyId: int): Option[ColonyInfo] =
  ## Find colony info by colony ID
  for colony in model.view.colonies:
    if colony.colonyId == colonyId:
      return some(colony)
  none(ColonyInfo)

proc selectedFleet*(model: TuiModel): Option[FleetInfo] =
  ## Get selected fleet
  if model.ui.mode != ViewMode.Fleets:
    return none(FleetInfo)
  let fleets = model.filteredFleets()
  if model.ui.selectedIdx < fleets.len:
    return some(fleets[model.ui.selectedIdx])
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
  of ViewMode.IntelDb: "Intel"
  of ViewMode.Settings: "Settings"
  of ViewMode.Messages: "Inbox"
  of ViewMode.PlanetDetail: "Colony"
  of ViewMode.FleetDetail: "Fleet"
  of ViewMode.IntelDetail: "Intel"

proc isPrimaryView*(mode: ViewMode): bool =
  ## Check if mode is a primary view (F-keys)
  mode in {ViewMode.Overview, ViewMode.Planets, ViewMode.Fleets,
           ViewMode.Research, ViewMode.Espionage, ViewMode.Economy,
           ViewMode.IntelDb, ViewMode.Settings,
           ViewMode.Messages}

proc isDetailView*(mode: ViewMode): bool =
  ## Check if mode is a detail/drill-down view
  mode in {ViewMode.PlanetDetail, ViewMode.FleetDetail,
           ViewMode.IntelDetail}

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
# Cursor Fleet Resolution Helpers
# =============================================================================

proc getCursorFleetId*(model: TuiModel): Option[int] =
  ## Returns the fleet ID under the cursor, considering view mode.
  ## ListView: uses selectedIdx + filteredFleets()
  ## SystemView: uses fleetConsoleSystemIdx + fleetConsoleFleetIdx
  if model.ui.fleetViewMode == FleetViewMode.ListView:
    let fleets = model.filteredFleets()
    if model.ui.selectedIdx < fleets.len:
      return some(fleets[model.ui.selectedIdx].id)
  elif model.ui.fleetViewMode == FleetViewMode.SystemView:
    let systems = model.ui.fleetConsoleSystems
    if systems.len > 0:
      let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
      let systemId = systems[sysIdx].systemId
      if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
        let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
        let fleetIdx = model.ui.fleetConsoleFleetIdx
        if fleetIdx >= 0 and fleetIdx < fleets.len:
          return some(fleets[fleetIdx].fleetId)
  return none(int)

proc getCursorFleetRoe*(model: TuiModel): int =
  ## Returns the ROE of the fleet under the cursor (default 6 if not found)
  if model.ui.fleetViewMode == FleetViewMode.ListView:
    let fleets = model.filteredFleets()
    if model.ui.selectedIdx < fleets.len:
      return fleets[model.ui.selectedIdx].roe
  elif model.ui.fleetViewMode == FleetViewMode.SystemView:
    let systems = model.ui.fleetConsoleSystems
    if systems.len > 0:
      let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
      let systemId = systems[sysIdx].systemId
      if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
        let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
        let fleetIdx = model.ui.fleetConsoleFleetIdx
        if fleetIdx >= 0 and fleetIdx < fleets.len:
          return fleets[fleetIdx].roe
  return 6  # Default standard ROE

# =============================================================================
# Zero-Turn Command Helpers
# =============================================================================

proc allZeroTurnCommands*(): seq[ZeroTurnCommandType] =
  ## Returns the 9 ZTC types in display order (1-9)
  @[ZeroTurnCommandType.DetachShips,
    ZeroTurnCommandType.TransferShips,
    ZeroTurnCommandType.MergeFleets,
    ZeroTurnCommandType.LoadCargo,
    ZeroTurnCommandType.UnloadCargo,
    ZeroTurnCommandType.LoadFighters,
    ZeroTurnCommandType.UnloadFighters,
    ZeroTurnCommandType.TransferFighters,
    ZeroTurnCommandType.Reactivate]

proc ztcLabel*(ztc: ZeroTurnCommandType): string =
  ## Human-readable label for a ZTC
  case ztc
  of ZeroTurnCommandType.DetachShips: "Detach Ships"
  of ZeroTurnCommandType.TransferShips: "Transfer Ships"
  of ZeroTurnCommandType.MergeFleets: "Merge Fleets"
  of ZeroTurnCommandType.LoadCargo: "Load Cargo"
  of ZeroTurnCommandType.UnloadCargo: "Unload Cargo"
  of ZeroTurnCommandType.LoadFighters: "Load Fighters"
  of ZeroTurnCommandType.UnloadFighters: "Unload Fighters"
  of ZeroTurnCommandType.TransferFighters: "Transfer Fighters"
  of ZeroTurnCommandType.Reactivate: "Reactivate"

proc ztcDescription*(ztc: ZeroTurnCommandType): string =
  ## Short description for a ZTC
  case ztc
  of ZeroTurnCommandType.DetachShips: "Split ships from fleet into new fleet"
  of ZeroTurnCommandType.TransferShips: "Move ships to another fleet (same system)"
  of ZeroTurnCommandType.MergeFleets: "Dissolve this fleet into another"
  of ZeroTurnCommandType.LoadCargo: "Load marines/colonists onto transport ships"
  of ZeroTurnCommandType.UnloadCargo: "Unload cargo from transport ships"
  of ZeroTurnCommandType.LoadFighters: "Load fighter ships from colony to carrier"
  of ZeroTurnCommandType.UnloadFighters: "Unload fighter ships from carrier to colony"
  of ZeroTurnCommandType.TransferFighters: "Transfer fighter ships between carriers"
  of ZeroTurnCommandType.Reactivate: "Return Reserved/Mothballed fleet to active"

proc ztcSourceFleetIds*(model: TuiModel): seq[int] =
  ## Source fleets for ZTC operations (batch selection or current fleet).
  if model.ui.selectedFleetIds.len > 0:
    return model.ui.selectedFleetIds
  if model.ui.fleetDetailModal.fleetId > 0:
    return @[model.ui.fleetDetailModal.fleetId]
  @[]

proc fleetHasOperationalClass(
    model: TuiModel,
    fleet: Fleet,
    shipClass: ShipClass
): bool =
  for shipId in fleet.ships:
    if int(shipId) notin model.view.ownShipsById:
      continue
    let ship = model.view.ownShipsById[int(shipId)]
    if ship.state == CombatState.Destroyed:
      continue
    if ship.shipClass == shipClass:
      return true
  false

proc fleetHasOperationalCarrier*(model: TuiModel, fleet: Fleet): bool =
  for shipId in fleet.ships:
    if int(shipId) notin model.view.ownShipsById:
      continue
    let ship = model.view.ownShipsById[int(shipId)]
    if ship.state == CombatState.Destroyed:
      continue
    if ship.shipClass in {ShipClass.Carrier, ShipClass.SuperCarrier}:
      return true
  false

proc fleetHasEmbarkedFighters*(model: TuiModel, fleet: Fleet): bool =
  for shipId in fleet.ships:
    if int(shipId) notin model.view.ownShipsById:
      continue
    let ship = model.view.ownShipsById[int(shipId)]
    if ship.state == CombatState.Destroyed:
      continue
    if ship.shipClass in {ShipClass.Carrier, ShipClass.SuperCarrier} and
        ship.embarkedFighters.len > 0:
      return true
  false

proc hasZtcTargetFleetSameLocation*(
    model: TuiModel,
    sourceFleetId: int,
    requireCarrier: bool = false
): bool =
  if sourceFleetId notin model.view.ownFleetsById:
    return false
  let source = model.view.ownFleetsById[sourceFleetId]
  for fleetId, fleet in model.view.ownFleetsById.pairs:
    if fleetId == sourceFleetId:
      continue
    if fleet.location != source.location:
      continue
    if requireCarrier and not model.fleetHasOperationalCarrier(fleet):
      continue
    return true
  false

proc ztcValidationErrorForFleet*(
    model: TuiModel,
    fleetId: int,
    ztcType: ZeroTurnCommandType
): string =
  ## Conservative client-side applicability checks for ZTC picker filtering.
  if fleetId notin model.view.ownFleetsById:
    return "Fleet not found"
  let fleet = model.view.ownFleetsById[fleetId]
  let atFriendlyColony = int(fleet.location) in model.view.ownColoniesBySystem
  case ztcType
  of ZeroTurnCommandType.DetachShips:
    if fleet.ships.len == 0:
      return "No ships"
  of ZeroTurnCommandType.TransferShips:
    if fleet.ships.len == 0:
      return "No ships"
    if not model.hasZtcTargetFleetSameLocation(fleetId):
      return "No target fleet at location"
  of ZeroTurnCommandType.MergeFleets:
    if not model.hasZtcTargetFleetSameLocation(fleetId):
      return "No target fleet at location"
  of ZeroTurnCommandType.LoadCargo:
    if not atFriendlyColony:
      return "Not at friendly colony"
    if not model.fleetHasOperationalClass(fleet, ShipClass.TroopTransport) and
        not model.fleetHasOperationalClass(fleet, ShipClass.ETAC):
      return "No cargo-capable ships"
  of ZeroTurnCommandType.UnloadCargo:
    if not atFriendlyColony:
      return "Not at friendly colony"
    var hasCargo = false
    for shipId in fleet.ships:
      if int(shipId) notin model.view.ownShipsById:
        continue
      let ship = model.view.ownShipsById[int(shipId)]
      if ship.state == CombatState.Destroyed:
        continue
      if ship.cargo.isSome and ship.cargo.get().quantity > 0:
        hasCargo = true
        break
    if not hasCargo:
      return "No cargo loaded"
  of ZeroTurnCommandType.LoadFighters:
    if not atFriendlyColony:
      return "Not at friendly colony"
    if not model.fleetHasOperationalCarrier(fleet):
      return "No operational carrier"
    if int(fleet.location) notin model.view.ownColoniesBySystem or
        model.view.ownColoniesBySystem[int(fleet.location)].fighterIds.len == 0:
      return "No colony fighters"
  of ZeroTurnCommandType.UnloadFighters:
    if not atFriendlyColony:
      return "Not at friendly colony"
    if not model.fleetHasEmbarkedFighters(fleet):
      return "No embarked fighters"
  of ZeroTurnCommandType.TransferFighters:
    if not model.fleetHasEmbarkedFighters(fleet):
      return "No embarked fighters"
    if not model.hasZtcTargetFleetSameLocation(fleetId, requireCarrier = true):
      return "No carrier target fleet"
  of ZeroTurnCommandType.Reactivate:
    if not atFriendlyColony:
      return "Not at friendly colony"
    if fleet.status == FleetStatus.Active:
      return "Fleet already active"
  ""

proc buildZtcPickerList*(model: TuiModel): seq[ZeroTurnCommandType] =
  ## Build applicable ZTC command list (single fleet or batch intersection).
  let sourceFleetIds = model.ztcSourceFleetIds()
  if sourceFleetIds.len == 0:
    return @[]
  result = @[]
  for ztcType in allZeroTurnCommands():
    var validForAll = true
    for fleetId in sourceFleetIds:
      if model.ztcValidationErrorForFleet(fleetId, ztcType).len > 0:
        validForAll = false
        break
    if validForAll:
      result.add(ztcType)

# =============================================================================
# ROE (Rules of Engagement) Helpers
# =============================================================================

proc roeLabel*(value: int): string =
  ## Get label for ROE value
  case value
  of 0: "Avoid"
  of 1: "Flee"
  of 2: "Flee"
  of 3: "Cautious"
  of 4: "Cautious"
  of 5: "Defensive"
  of 6: "Standard"
  of 7: "Aggressive"
  of 8: "Aggressive"
  of 9: "Desperate"
  of 10: "Suicidal"
  else: "Unknown"

proc roeDescription*(value: int): string =
  ## Get meaning for ROE value (from spec 7.2.3)
  case value
  of 0: "Avoid all hostile forces"
  of 1: "Engage only defenseless"
  of 2: "Need 4:1 advantage"
  of 3: "Need 3:1 advantage"
  of 4: "Need 2:1 advantage"
  of 5: "Need 3:2 advantage"
  of 6: "Fight if equal or superior"
  of 7: "Fight even at 2:3 disadvantage"
  of 8: "Fight even at 1:2 disadvantage"
  of 9: "Fight even at 1:3 disadvantage"
  of 10: "Fight regardless of odds"
  else: ""

proc roeUseCase*(value: int): string =
  ## Use case for ROE value (from spec 7.2.3)
  case value
  of 0: "Pure scouts, intel gathering"
  of 1: "Extreme caution"
  of 2: "Scout fleets, recon forces"
  of 3: "Cautious patrols"
  of 4: "Conservative operations"
  of 5: "Defensive posture"
  of 6: "Standard combat fleets"
  of 7: "Aggressive fleets"
  of 8: "Battle fleets"
  of 9: "Desperate defense"
  of 10: "Suicidal last stands, homeworld defense"
  else: ""

# =============================================================================
# Expert Mode Helpers
# =============================================================================

proc clearExpertFeedback*(model: var TuiModel) =
  ## Clear expert mode feedback message
  model.ui.expertModeFeedback = ""

proc enterExpertMode*(model: var TuiModel) =
  ## Enter expert mode
  model.ui.expertModeActive = true
  model.ui.expertModeInput.clear()
  model.ui.expertPaletteSelection = 0
  model.clearExpertFeedback()

proc exitExpertMode*(model: var TuiModel) =
  ## Exit expert mode
  model.ui.expertModeActive = false
  model.ui.expertModeInput.clear()
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
  var count = model.ui.stagedFleetCommands.len +
    model.ui.stagedZeroTurnCommands.len +
    model.ui.stagedBuildCommands.len +
    model.ui.stagedRepairCommands.len +
    model.ui.stagedScrapCommands.len +
    model.ui.stagedColonyManagement.len
  if model.ui.stagedEbpInvestment > 0:
    count.inc
  if model.ui.stagedCipInvestment > 0:
    count.inc
  count += model.ui.stagedEspionageActions.len
  count

proc espionageQueuedQty*(
    model: TuiModel,
    target: HouseId,
    action: EspionageAction
): int =
  for attempt in model.ui.stagedEspionageActions:
    if attempt.target == target and attempt.action == action:
      result.inc

proc espionageQueuedTotalEbp*(model: TuiModel): int =
  for attempt in model.ui.stagedEspionageActions:
    result += espionageActionCost(attempt.action)

proc espionageEbpTotal*(model: TuiModel): int =
  let pool =
    if model.view.espionageEbpPool.isSome:
      model.view.espionageEbpPool.get()
    else:
      0
  pool + int(model.ui.stagedEbpInvestment)

proc espionageEbpAvailable*(model: TuiModel): int =
  max(0, model.espionageEbpTotal() - model.espionageQueuedTotalEbp())

proc espionageCipTotal*(model: TuiModel): int =
  let pool =
    if model.view.espionageCipPool.isSome:
      model.view.espionageCipPool.get()
    else:
      0
  pool + int(model.ui.stagedCipInvestment)

proc stagedCommandEntries*(model: TuiModel): seq[StagedCommandEntry] =
  ## Get flattened list of staged commands in display order
  result = @[]
  for fleetId in model.ui.stagedFleetCommands.keys:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.Fleet, index: fleetId))
  for idx in 0 ..< model.ui.stagedZeroTurnCommands.len:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.ZeroTurn, index: idx))
  for idx in 0 ..< model.ui.stagedBuildCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Build, index: idx))
  for idx in 0 ..< model.ui.stagedRepairCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Repair, index: idx))
  for idx in 0 ..< model.ui.stagedScrapCommands.len:
    result.add(StagedCommandEntry(kind: StagedCommandKind.Scrap, index: idx))
  for idx in 0 ..< model.ui.stagedColonyManagement.len:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.ColonyManagement, index: idx))
  if model.ui.stagedEbpInvestment > 0:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.EspionageBudget, index: 0))
  if model.ui.stagedCipInvestment > 0:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.EspionageBudget, index: 1))
  for idx in 0 ..< model.ui.stagedEspionageActions.len:
    result.add(StagedCommandEntry(
      kind: StagedCommandKind.EspionageAction, index: idx))

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

proc formatColonyManagementOrder*(cmd: ColonyManagementCommand): string =
  ## Format colony automation toggle command for display
  proc onOff(value: bool): string =
    if value: "ON" else: "OFF"
  result =
    "Colony " & $int(cmd.colonyId) & ": Auto " &
    "Repair " & onOff(cmd.autoRepair) &
    "  Marines " & onOff(cmd.autoLoadMarines) &
    "  Fighters " & onOff(cmd.autoLoadFighters)

proc formatEspionageBudgetOrder*(
    model: TuiModel,
    channelIdx: int
): string =
  let ebpCostPp = int(gameConfig.espionage.costs.ebpCostPp)
  let cipCostPp = int(gameConfig.espionage.costs.cipCostPp)
  if channelIdx == 0:
    let points = int(model.ui.stagedEbpInvestment)
    return "Espionage Budget: EBP +" & $points & " (" &
      $(points * ebpCostPp) & " PP)"
  let points = int(model.ui.stagedCipInvestment)
  "Espionage Budget: CIP +" & $points & " (" &
    $(points * cipCostPp) & " PP)"

proc formatEspionageActionOrder*(
    model: TuiModel,
    idx: int
): string =
  if idx < 0 or idx >= model.ui.stagedEspionageActions.len:
    return "Espionage action " & $idx
  let attempt = model.ui.stagedEspionageActions[idx]
  let targetName = model.view.houseNames.getOrDefault(
    int(attempt.target), "House " & $int(attempt.target)
  )
  let actionLabel = espionageActionLabel(attempt.action)
  let cost = espionageActionCost(attempt.action)
  actionLabel & " vs " & targetName & " (" & $cost & " EBP)"

proc formatZeroTurnOrder*(cmd: ZeroTurnCommand): string =
  ## Format a zero-turn command for staged list display.
  result = "ZTC " & $cmd.commandType
  if cmd.sourceFleetId.isSome:
    result.add(" src=" & $cmd.sourceFleetId.get())
  if cmd.targetFleetId.isSome:
    result.add(" dst=" & $cmd.targetFleetId.get())

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
        formatFleetOrder(
          model.ui.stagedFleetCommands[entry.index])
      of StagedCommandKind.ZeroTurn:
        formatZeroTurnOrder(
          model.ui.stagedZeroTurnCommands[entry.index]
        )
      of StagedCommandKind.Build:
        formatBuildOrder(model.ui.stagedBuildCommands[entry.index])
      of StagedCommandKind.Repair:
        "Repair command " & $entry.index
      of StagedCommandKind.Scrap:
        "Scrap command " & $entry.index
      of StagedCommandKind.ColonyManagement:
        formatColonyManagementOrder(
          model.ui.stagedColonyManagement[entry.index])
      of StagedCommandKind.EspionageBudget:
        formatEspionageBudgetOrder(model, entry.index)
      of StagedCommandKind.EspionageAction:
        formatEspionageActionOrder(model, entry.index)
    lines.add("  " & $(idx + 1) & ". " & label)
  lines.join(" | ")

proc dropStagedCommand*(model: var TuiModel, entry: StagedCommandEntry): bool =
  ## Remove staged command by entry
  case entry.kind
  of StagedCommandKind.Fleet:
    if entry.index in model.ui.stagedFleetCommands:
      model.ui.stagedFleetCommands.del(entry.index)
      return true
  of StagedCommandKind.ZeroTurn:
    if entry.index < model.ui.stagedZeroTurnCommands.len:
      model.ui.stagedZeroTurnCommands.delete(entry.index)
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
  of StagedCommandKind.ColonyManagement:
    if entry.index < model.ui.stagedColonyManagement.len:
      model.ui.stagedColonyManagement.delete(entry.index)
      return true
  of StagedCommandKind.EspionageBudget:
    if entry.index == 0 and model.ui.stagedEbpInvestment > 0:
      model.ui.stagedEbpInvestment = 0
      return true
    if entry.index == 1 and model.ui.stagedCipInvestment > 0:
      model.ui.stagedCipInvestment = 0
      return true
  of StagedCommandKind.EspionageAction:
    if entry.index < model.ui.stagedEspionageActions.len:
      model.ui.stagedEspionageActions.delete(entry.index)
      return true
  false

# =============================================================================
# Command Picker Helpers
# =============================================================================

proc validateFleetCommand*(fleet: FleetInfo,
  cmdType: FleetCommandType): string

proc needsTargetSystem*(cmdType: int): bool =
  ## Check if a command type needs target system selection.
  ## Hold (00) auto-targets current location, SeekHome (02)
  ## auto-computes nearest drydock, JoinFleet (14) uses
  ## FleetPicker.
  cmdType in [CmdMove, CmdPatrol, CmdGuardStarbase,
              CmdGuardColony, CmdBlockade, CmdBombard,
              CmdInvade, CmdBlitz, CmdColonize,
              CmdScoutColony, CmdScoutSystem,
              CmdHackStarbase, CmdRendezvous, CmdSalvage,
              CmdReserve, CmdMothball, CmdView]

proc buildCommandPickerList*(model: TuiModel): seq[FleetCommandType] =
  result = @[]
  let commands = allFleetCommands()

  if model.ui.selectedFleetIds.len > 0:
    var selectedFleets: seq[FleetInfo]
    for fleet in model.view.fleets:
      if fleet.id in model.ui.selectedFleetIds:
        selectedFleets.add(fleet)
    for cmdType in commands:
      if cmdType == FleetCommandType.JoinFleet:
        continue
      var validForAll = true
      for fleet in selectedFleets:
        if validateFleetCommand(fleet, cmdType).len > 0:
          validForAll = false
          break
      if validForAll:
        result.add(cmdType)
    return

  var currentFleet: Option[FleetInfo]
  for fleet in model.view.fleets:
    if fleet.id == model.ui.fleetDetailModal.fleetId:
      currentFleet = some(fleet)
      break
  if currentFleet.isNone:
    result = commands
    return
  let current = currentFleet.get()
  for cmdType in commands:
    if validateFleetCommand(current, cmdType).len == 0:
      result.add(cmdType)

# =============================================================================
# System Picker Helpers
# =============================================================================

proc buildSystemPickerList*(
    model: TuiModel): seq[SystemPickerEntry] =
  ## Build a sorted list of all known systems for the
  ## SystemPicker sub-modal.
  result = @[]
  for coord, sys in model.view.systems.pairs:
    result.add(SystemPickerEntry(
      systemId: sys.id,
      name: sys.name,
      coordLabel: coordLabel(coord)
    ))
  result.sort(proc(a, b: SystemPickerEntry): int =
    cmp(a.coordLabel, b.coordLabel)
  )

proc filterSystemsBySet(
    systems: seq[SystemPickerEntry],
    allowed: HashSet[int]
): seq[SystemPickerEntry] =
  result = @[]
  for sys in systems:
    if sys.systemId in allowed:
      result.add(sys)

proc buildSystemPickerListForCommand*(
    model: TuiModel,
    cmdType: FleetCommandType
): SystemPickerFilterResult =
  let allSystems = model.buildSystemPickerList()
  result.systems = allSystems
  result.emptyMessage = ""

  var ownedColonies = initHashSet[int]()
  var ownedStarbases = initHashSet[int]()
  var salvageSystems = initHashSet[int]()

  for row in model.view.planetsRows:
    if row.isOwned:
      ownedColonies.incl(row.systemId)
      if row.starbaseCount > 0:
        ownedStarbases.incl(row.systemId)
      if row.cdTotal.isSome and row.cdTotal.get > 0:
        salvageSystems.incl(row.systemId)

  var knownEnemyStarbases = initHashSet[int]()
  for row in model.view.intelRows:
    if row.starbaseCount.isSome and row.starbaseCount.get > 0:
      if row.systemId in model.view.knownEnemyColonySystemIds:
        knownEnemyStarbases.incl(row.systemId)

  case cmdType
  of FleetCommandType.GuardStarbase:
    result.systems = filterSystemsBySet(
      allSystems, ownedStarbases
    )
    result.emptyMessage = "No friendly starbases found"
  of FleetCommandType.GuardColony:
    result.systems = filterSystemsBySet(
      allSystems, ownedColonies
    )
    result.emptyMessage = "No friendly colonies found"
  of FleetCommandType.Blockade:
    result.systems = filterSystemsBySet(
      allSystems, model.view.knownEnemyColonySystemIds
    )
    result.emptyMessage = "No known enemy colonies to blockade"
  of FleetCommandType.Bombard:
    result.systems = filterSystemsBySet(
      allSystems, model.view.knownEnemyColonySystemIds
    )
    result.emptyMessage = "No known enemy colonies to bombard"
  of FleetCommandType.Invade:
    result.systems = filterSystemsBySet(
      allSystems, model.view.knownEnemyColonySystemIds
    )
    result.emptyMessage = "No known enemy colonies to invade"
  of FleetCommandType.Blitz:
    result.systems = filterSystemsBySet(
      allSystems, model.view.knownEnemyColonySystemIds
    )
    result.emptyMessage = "No known enemy colonies to blitz"
  of FleetCommandType.HackStarbase:
    result.systems = filterSystemsBySet(
      allSystems, knownEnemyStarbases
    )
    result.emptyMessage = "No known enemy starbases to hack"
  of FleetCommandType.Salvage:
    result.systems = filterSystemsBySet(
      allSystems, salvageSystems
    )
    result.emptyMessage = "No friendly colonies with salvage facilities"
  of FleetCommandType.Reserve, FleetCommandType.Mothball:
    result.systems = filterSystemsBySet(
      allSystems, ownedColonies
    )
    result.emptyMessage = "No friendly colonies found"
  else:
    discard

# =============================================================================
# Client-Side ETA Estimation (for optimistic updates)
# =============================================================================

const
  LaneTypeMajor = 0  ## Matches LaneClass.Major ord
  LaneTypeRestricted = 2  ## Matches LaneClass.Restricted

type EtaPathNode = tuple[f: uint32, system: int]

proc `<`(a, b: EtaPathNode): bool = a.f < b.f

proc hexDist(
    coords: Table[int, HexCoord],
    a: int, b: int,
): uint32 =
  ## Hex distance heuristic for A*.
  ## Falls back to 1 if coords missing.
  if coords.hasKey(a) and coords.hasKey(b):
    let ca = coords[a]
    let cb = coords[b]
    let dq = abs(ca.q - cb.q)
    let dr = abs(ca.r - cb.r)
    let ds = abs((-ca.q - ca.r) - (-cb.q - cb.r))
    return uint32(max(dq, max(dr, ds)))
  return 1'u32

proc estimateETA*(model: TuiModel,
    fromSys: int, toSys: int,
    etacOnly: bool = false): int =
  ## Estimate turns to travel from fromSys to toSys
  ## using A* pathfinding and turn-by-turn sim.
  ## Set etacOnly=true for ETAC-only fleets that
  ## can traverse Restricted lanes.
  ## Returns 0 if same system or unreachable.
  if fromSys == toSys:
    return 0

  # A* pathfinding with lane-cost weights
  var openSet: HeapQueue[EtaPathNode]
  var cameFrom = initTable[int, int]()
  var gScore = initTable[int, uint32]()

  gScore[fromSys] = 0'u32
  let h = hexDist(
    model.view.systemCoords, fromSys, toSys
  )
  openSet.push((h, fromSys))

  var found = false
  while openSet.len > 0:
    let current = openSet.pop().system
    if current == toSys:
      found = true
      break

    let neighs =
      model.view.laneNeighbors.getOrDefault(
        current, @[]
      )
    for neighbor in neighs:
      let lt =
        model.view.laneTypes.getOrDefault(
          (current, neighbor), -1
        )
      # Skip Restricted lanes for non-ETAC fleets
      if lt == LaneTypeRestricted and not etacOnly:
        continue

      let edgeCost: uint32 =
        case lt
        of LaneTypeMajor: 1'u32
        of 1: 2'u32  # Minor
        else: 3'u32  # Restricted or unknown
      let tentG = gScore[current] + edgeCost
      if neighbor notin gScore or
          tentG < gScore[neighbor]:
        cameFrom[neighbor] = current
        gScore[neighbor] = tentG
        let fVal = tentG + hexDist(
          model.view.systemCoords,
          neighbor, toSys,
        )
        openSet.push((fVal, neighbor))

  if not found:
    return 0  # Unreachable

  # Reconstruct path
  var path: seq[int] = @[toSys]
  var node = toSys
  while node != fromSys:
    node = cameFrom[node]
    path.insert(node, 0)

  # Turn-by-turn simulation
  var pos = 0
  var turns = 0

  while pos < path.len - 1:
    turns += 1
    var jumps = 1

    if pos + 2 < path.len:
      var allOwned = true
      for i in pos .. min(pos + 2, path.len - 1):
        if path[i] notin model.view.ownedSystemIds:
          allOwned = false
          break

      if allOwned:
        var bothMajor = true
        for i in pos ..< pos + 2:
          let lt =
            model.view.laneTypes.getOrDefault(
              (path[i], path[i + 1]), -1
            )
          if lt != LaneTypeMajor:
            bothMajor = false
            break
        if bothMajor:
          jumps = 2

    pos += min(jumps, path.len - 1 - pos)

  return turns

# =============================================================================
# Fleet Command Staging (optimistic update)
# =============================================================================

proc systemNameById(model: TuiModel, systemId: int): string =
  ## Look up system coord label by ID via O(1) lookup
  if model.view.systemCoords.hasKey(systemId):
    let c = model.view.systemCoords[systemId]
    return coordLabel(c.q, c.r)
  "-"

proc updateFleetInfoFromStagedCommand(model: var TuiModel, cmd: FleetCommand) =
  ## Optimistically update FleetInfo (ListView) and FleetConsoleFleet (SystemView)
  ## to reflect a staged command so fleet tables show new values immediately.
  let cmdNum = fleetCommandNumber(cmd.commandType)
  let cmdLbl = commandLabel(cmdNum)
  let newRoe = if cmd.roe.isSome: int(cmd.roe.get()) else: -1
  let isStationary = cmd.commandType in {
    FleetCommandType.Hold, FleetCommandType.SeekHome}
  var destLabel = ""
  var destSystemId = 0
  if cmd.commandType == FleetCommandType.JoinFleet and
      cmd.targetFleet.isSome:
    let targetId = int(cmd.targetFleet.get())
    var targetName = ""
    for fleet in model.view.fleets:
      if fleet.id == targetId:
        targetName = fleet.name
        break
    if targetName.len > 0:
      destLabel = "Fleet " & targetName
    else:
      destLabel = "Fleet " & $targetId
  elif cmd.targetSystem.isSome:
    destLabel = model.systemNameById(int(cmd.targetSystem.get()))
    destSystemId = int(cmd.targetSystem.get())
  elif isStationary:
    destLabel = "-"
  let fid = int(cmd.fleetId)

  # Update FleetInfo in model.view.fleets (ListView)
  for fleet in model.view.fleets.mitems:
    if fleet.id == fid:
      fleet.command = cmdNum
      fleet.commandLabel = cmdLbl
      fleet.isIdle = cmd.commandType == FleetCommandType.Hold
      if newRoe >= 0: fleet.roe = newRoe
      if destLabel.len > 0:
        fleet.destinationLabel = destLabel
        fleet.destinationSystemId = destSystemId
      if isStationary:
        fleet.eta = 0
      elif cmd.targetSystem.isSome:
        let isEtacOnly = fleet.hasEtacs and
          not fleet.hasCombatShips and
          not fleet.hasScouts and
          not fleet.hasTroopTransports and
          not fleet.hasCrippled and
          fleet.shipCount > 0
        fleet.eta = model.estimateETA(
          fleet.location,
          int(cmd.targetSystem.get()),
          isEtacOnly,
        )
      fleet.needsAttention = false
      break

  # Update FleetConsoleFleet in fleetConsoleFleetsBySystem (SystemView)
  for systemId, fleets in model.ui.fleetConsoleFleetsBySystem.mpairs:
    for flt in fleets.mitems:
      if flt.fleetId == fid:
        flt.commandLabel = cmdLbl
        if newRoe >= 0:
          flt.roe = newRoe
        if destLabel.len > 0:
          flt.destinationLabel = destLabel
        flt.needsAttention = false
        if isStationary:
          flt.eta = 0
        elif cmd.targetSystem.isSome:
          let isEtacOnly =
            flt.etacs > 0 and
            flt.shipCount == flt.etacs
          flt.eta = model.estimateETA(
            systemId,
            int(cmd.targetSystem.get()),
            isEtacOnly,
          )
        return

proc stageFleetCommand*(model: var TuiModel, cmd: FleetCommand) =
  ## Stage a fleet command and optimistically update fleet display data.
  ## Single entry point — all fleet command staging goes through here.
  ## Uses table keyed by fleetId so re-staging the same fleet replaces
  ## the previous command (one fleet, one staged command).
  model.ui.stagedFleetCommands[int(cmd.fleetId)] = cmd
  model.updateFleetInfoFromStagedCommand(cmd)

proc updateStagedROE*(model: var TuiModel,
    fleetId: int, newRoe: int) =
  ## Update ROE without changing the fleet's command.
  ## If a staged command exists for this fleet, update its
  ## ROE in-place. Otherwise reconstruct a command from the
  ## fleet's current displayed state so the command type,
  ## target, etc. are preserved.
  if fleetId in model.ui.stagedFleetCommands:
    model.ui.stagedFleetCommands[fleetId].roe =
      some(int32(newRoe))
    model.updateFleetInfoFromStagedCommand(
      model.ui.stagedFleetCommands[fleetId])
  else:
    # No staged command — preserve current command
    var cmdType = FleetCommandType.Hold
    var targetSys = none(SystemId)
    for fleet in model.view.fleets:
      if fleet.id == fleetId:
        cmdType = FleetCommandType(fleet.command)
        if fleet.destinationSystemId > 0:
          targetSys = some(
            SystemId(fleet.destinationSystemId.uint32))
        break
    let cmd = FleetCommand(
      fleetId: FleetId(fleetId.uint32),
      commandType: cmdType,
      targetSystem: targetSys,
      targetFleet: none(FleetId),
      roe: some(int32(newRoe))
    )
    model.stageFleetCommand(cmd)

# =============================================================================
# Order Entry — Target Selection
# =============================================================================

proc queueImmediateOrder*(model: var TuiModel, fleetId: int, cmdType: int) =
  ## Stage an immediate order (no target needed, like Hold)
  let cmd = FleetCommand(
    fleetId: FleetId(fleetId.uint32),
    commandType: FleetCommandType(cmdType),
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    roe: none(int32)
  )
  model.stageFleetCommand(cmd)

proc validateFleetCommand*(fleet: FleetInfo,
    cmdType: FleetCommandType): string =
  ## Returns empty string if valid, or error message if fleet doesn't meet
  ## command requirements per 06-operations.md spec
  case cmdType
  of FleetCommandType.GuardStarbase,
     FleetCommandType.GuardColony,
     FleetCommandType.Blockade,
     FleetCommandType.Bombard:
    if not fleet.hasCombatShips:
      return "Requires combat ship(s)"
  of FleetCommandType.Invade:
    if not fleet.hasCombatShips or not fleet.hasTroopTransports:
      return "Requires combat ship(s) & loaded Transports"
  of FleetCommandType.Blitz:
    if not fleet.hasTroopTransports:
      return "Requires loaded Troop Transports"
  of FleetCommandType.Colonize:
    if not fleet.hasEtacs:
      return "Requires one ETAC"
  of FleetCommandType.ScoutColony,
     FleetCommandType.ScoutSystem,
     FleetCommandType.HackStarbase:
    if not fleet.isScoutOnly:
      return "Requires scout-only fleet (1+ scouts)"
  else:
    discard  # Hold, Move, Patrol, etc. have no composition requirements
  return ""

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
    zeroTurnCommands: model.ui.stagedZeroTurnCommands,
    fleetCommands: model.ui.stagedFleetCommands.values.toSeq,
    buildCommands: model.ui.stagedBuildCommands,
    repairCommands: model.ui.stagedRepairCommands,
    scrapCommands: model.ui.stagedScrapCommands,
    # Empty/default values for other command types (Phase 2+)
    researchAllocation: model.ui.researchAllocation,
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: model.ui.stagedColonyManagement,
    espionageActions: model.ui.stagedEspionageActions,
    ebpInvestment: model.ui.stagedEbpInvestment,
    cipInvestment: model.ui.stagedCipInvestment
  )
