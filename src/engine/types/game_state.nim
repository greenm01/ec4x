import std/[tables, options]
import ./[
  core, house, starmap, colony, fleet, squadron, ship, ground_unit,
  intelligence, diplomacy, facilities, production, espionage,
  prestige, population, capacity, resolution, progression
]

type
  GameState* = object
    counters*: IdCounters
    gameId*: int32
    turn*: int32
    phase*: GamePhase
    seed*: int64
    turnDeadline*: int64
    
    # Entity collections (DoD)
    houses*: Houses
    systems*: Systems
    colonies*: Colonies
    # Military Units
    fleets*: Fleets
    squadrons*: Squadrons
    ships*: Ships
    groundUnits*: GroundUnits
    # Facilities
    starbases*: StarBases
    spacePorts*: SpacePorts
    shipYards*: ShipYards
    dryDocks*: DryDocks

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
    
  IdCounters* = object
    nextPlayerId*: uint32
    nextHouseId*: uint32
    nextSystemId*: uint32
    nextColonyId*: uint32
    nextStarbaseId*: uint32
    nextSpaceportId*: uint32
    nextShipyardId*: uint32
    nextDrydockId*: uint32
    nextFleetId*: uint32
    nextSquadronId*: uint32
    nextShipId*: uint32
    nextGroundUnitId*: uint32
    nextConstructionProjectId*: uint32
    nextRepairProjectId*: uint32
    nextPopulationTransferId*: uint32

  GamePhase* {.pure.} = enum
    Conflict, Income, Command, Production

