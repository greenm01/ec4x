import std/[tables, options]
import ./[
  core, house, starmap, colony, fleet, squadron, ship, ground_unit,
  intelligence, diplomacy, facilities, production, espionage,
  prestige, population, capacity, resolution, progression
]

type
  GamePhase* {.pure.} = enum
    Conflict, Income, Command, Production

  GameState* = object
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
