import std/tables
import./[
  core, house, starmap, colony, fleet, ship, ground_unit,
  intel, diplomacy, facilities, production, espionage,
  population, resolution, progression, event
]

type
  GamePhase* {.pure.} = enum
    Conflict
    Income
    Command
    Production

  GracePeriodTracker* = object
    ## Tracks grace periods for capacity enforcement
    ## Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
    fighterCapacityExpiry*: Table[SystemId, int] # Per-colony fighter grace

  GameState* = ref object
    gameId*: string
    gameName*: string # Human-readable name
    gameDescription*: string # Optional admin notes
    turn*: int32
    phase*: GamePhase
    seed*: int64
    turnDeadline*: int64

    # Persistence
    dbPath*: string # Path to per-game SQLite database
    dataDir*: string # Root data directory

    # Map
    starMap*: StarMap

    # Entity collections (DoD)
    houses*: Houses
    systems*: Systems
    colonies*: Colonies
    fleets*: Fleets
    ships*: Ships
    groundUnits*: GroundUnits

    # Intelligence databases - one per house
    intel*: Table[HouseId, IntelDatabase]

    # Diplomacy
    diplomaticRelation*: Table[(HouseId, HouseId), DiplomaticRelation]
    diplomaticViolation*: Table[HouseId, ViolationHistory]

    # Facilities (unified types)
    neorias*: Neorias
    kastras*: Kastras

    # Production
    constructionProjects*: ConstructionProjects
    repairProjects*: RepairProjects

    counters*: IdCounters

    # Phase-specific state
    ongoingEffects*: seq[OngoingEffect]
    pendingProposals*: seq[PendingProposal]

    # Commissioning queues
    pendingCommissions*: seq[CompletedProject]
    gracePeriodTimers*: Table[HouseId, GracePeriodTracker]

    # Game progression
    actProgression*: ActProgressionState

    # Reports (transient, cleared each turn)
    lastTurnReports*: Table[HouseId, TurnResolutionReport]
    lastTurnEvents*: seq[GameEvent] # Event stream for telemetry
    scoutLossEvents*: seq[ScoutLossEvent]

    # Population Transfers
    populationTransfers*: PopulationTransfers
