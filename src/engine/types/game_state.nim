import std/[tables, options]
import ./[
  core, house, starmap, colony, fleet, squadron, ship, ground_unit,
  intelligence, diplomacy, facilities, production, espionage,
  prestige, population, capacity, resolution, progression
]

type
  GameAct* {.pure.} = enum
    ## 4-Act game structure that scales with map size
    ## Each act has different strategic priorities
    Act1_LandGrab,      # Turns 1-7: Rapid colonization, exploration
    Act2_RisingTensions, # Turns 8-15: Consolidation, military buildup, diplomacy
    Act3_TotalWar,      # Turns 16-25: Major conflicts, invasions
    Act4_Endgame        # Turns 26-30: Final push for victory

  GamePhase* {.pure.} = enum
    Conflict, Income, Command, Production

  ActProgressionState* = object
    ## Global game act progression tracking (public information)
    ## Prestige and planet counts are on public leaderboard, so no FOW restrictions
    ## Per docs/ai/architecture/ai_architecture.adoc lines 279-300
    currentAct*: GameAct
    actStartTurn*: int32

    # Act 2 tracking: Snapshot top 3 houses at Act 2 start (90% colonization)
    act2TopThreeHouses*: seq[HouseId]
    act2TopThreePrestige*: seq[int]

    # Cached values for transition gates (diagnostics)
    lastColonizationPercent*: float32
    lastTotalPrestige*: int32

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
