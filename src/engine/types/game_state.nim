import std/tables
import ./[
  core, house, starmap, colony, fleet, squadron, ship, ground_unit,
  intelligence, diplomacy, facilities, production, espionage,
  population, resolution, progression
]

type
  GamePhase* {.pure.} = enum
    Conflict, Income, Command, Production

  GracePeriodTracker* = object
    ## Tracks grace periods for capacity enforcement
    ## Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
    totalSquadronsExpiry*: int32  # Turn when total squadron grace expires
    fighterCapacityExpiry*: Table[SystemId, int]  # Per-colony fighter grace

  GameState* = ref object
    gameId*: int32
    turn*: int32
    phase*: GamePhase
    seed*: int64
    turnDeadline*: int64
    
    # Entity collections (DoD)
    houses*: Houses
    systems*: Systems
    colonies*: Colonies
    fleets*: Fleets
    squadrons*: Squadrons
    ships*: Ships
    groundUnits*: GroundUnits

    # Intelligence databases - one per house
    intelligence*: Table[HouseId, IntelligenceDatabase]

    # Diplomacy
    diplomaticRelation*: Table[(HouseId, HouseId), DiplomaticRelation]
    diplomaticViolation*: Table[HouseId, ViolationHistory]
     
    # Facilities
    starbases*: Starbases
    spaceports*: Spaceports
    shipyards*: Shipyards
    drydocks*: Drydocks
    
    # Production
    constructionProjects*: ConstructionProjects
    repairProjects*: RepairProjects

    counters*: IdCounters
        
    # Map
    starMap*: StarMap
    
    # Phase-specific state
    arrivedFleets*: Table[FleetId, SystemId]
    activeSpyMissions*: Table[FleetId, ActiveSpyMission]
    ongoingEffects*: seq[OngoingEffect]
    pendingProposals*: seq[PendingProposal]
    populationInTransit*: seq[PopulationInTransit]
    
    # Commissioning queues
    pendingCommissions*: seq[CompletedProject]
    gracePeriodTimers*: Table[HouseId, GracePeriodTracker]
    
    # Game progression
    actProgression*: ActProgressionState
    
    # Reports (transient, cleared each turn)
    lastTurnReports*: Table[HouseId, TurnResolutionReport]
    scoutLossEvents*: seq[ScoutLossEvent]

    # Population Transfers
    populationTransfers*: PopulationTransfers
