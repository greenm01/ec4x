## Core Game State Types for EC4X
##
## This module consolidates all primary data structures used in the EC4X engine.
## It adheres to the Data-Oriented Design (DoD) principle by separating data
## definitions from behavior.
##
## All game entities (GameState, House, Colony, Fleet, Squadron, etc.) and
## their related types are defined here.

import std/[tables, options]
import ../../common/types/[planets, tech, diplomacy]
import ../fleet
import ../starmap
import ../squadron
import ../orders  # For FleetOrder
import ../config/[military_config, economy_config]
import ../ai/rba/config  # For ActProgressionConfig
import ../diagnostics_data
import ../diplomacy/types as dip_types
import ../diplomacy/proposals as dip_proposals
import ../espionage/types as esp_types
import ../research/types as res_types
import ../research/effects  # CST dock capacity calculations
import ../economy/types as econ_types
import ../population/types as pop_types
import ../intelligence/types as intel_types
import ../map/types # Import Hex and System related types
import ../types/colony_types

type
  GameAct* {.pure.} = enum
    ## 4-Act game structure that scales with map size
    ## Each act has different strategic priorities
    Act1_LandGrab,      # Turns 1-7: Rapid colonization, exploration
    Act2_RisingTensions, # Turns 8-15: Consolidation, military buildup, diplomacy
    Act3_TotalWar,      # Turns 16-25: Major conflicts, invasions
    Act4_Endgame        # Turns 26-30: Final push for victory

# Re-export common types
export core.HouseId, core.SystemId, core.FleetId
export planets.PlanetClass, planets.ResourceRating
export tech.TechField, tech.TechLevel
export diplomacy.DiplomaticState
export fleet.SquadronType, fleet.ShipCargo, fleet.CargoType
export GameAct # Re-export GameAct for external modules

type
  FallbackRoute* = object
    ## Designated safe retreat route for a region
    ## Planned retreat destinations updated by AI strategy or automatic safety checks
    region*: SystemId           # Region anchor (usually a colony)
    fallbackSystem*: SystemId   # Safe retreat destination
    lastUpdated*: int           # Turn when route was validated

  AutoRetreatPolicy* {.pure.} = enum
    ## Player setting for automatic fleet retreats
    Never,              # Never auto-retreat (player always controls)
    MissionsOnly,       # Only abort missions (ETAC, Guard, Blockade) when target lost
    ConservativeLosing, # Retreat fleets when clearly losing combat
    AggressiveSurvival  # Retreat any fleet at risk of destruction

  HouseStatus* {.pure.} = enum
    ## Player/house operational status (gameplay.md:1.4)
    Active,              # Normal play - submitting orders
    Autopilot,           # Temporary MIA mode (3+ consecutive turns without orders)
    DefensiveCollapse    # Permanent elimination (3+ consecutive turns prestige < 0)

  House* = object
    id*: HouseId
    name*: string
    color*: string                # For UI/map display
    prestige*: int                # Victory points
    treasury*: int                # Accumulated wealth
    techTree*: res_types.TechTree
    eliminated*: bool
    status*: HouseStatus         # Operational status (Active, Autopilot, DefensiveCollapse)
    negativePrestigeTurns*: int  # Consecutive turns with prestige < 0 (defensive collapse)
    turnsWithoutOrders*: int     # Consecutive turns without submitting orders (MIA autopilot)
    diplomaticRelations*: dip_types.DiplomaticRelations  # Relations with other houses
    violationHistory*: dip_types.ViolationHistory  # Track violations
    espionageBudget*: esp_types.EspionageBudget  # EBP/CIP points
    taxPolicy*: econ_types.TaxPolicy  # Current tax rate and 6-turn history
    consecutiveShortfallTurns*: int  # Consecutive turns of missed maintenance payment (economy.md:3.11)

    # Planet-Breaker tracking (assets.md:2.4.8)
    planetBreakerCount*: int  # Current PB count (max = current colony count)

    # Intelligence database (intel.md)
    intelligence*: intel_types.IntelligenceDatabase  # Gathered intelligence reports

    # Economic reports (for intelligence gathering)
    latestIncomeReport*: Option[econ_types.HouseIncomeReport]  # Last turn's income report

    # Safe retreat routes (automatic seek-home behavior)
    fallbackRoutes*: seq[FallbackRoute]  # Pre-planned retreat destinations
    autoRetreatPolicy*: AutoRetreatPolicy  # Player's auto-retreat preference

  GamePhase* {.pure.} = enum
    Setup, Active, Paused, Completed

  ActProgressionState* = object
    ## Global game act progression tracking (public information)
    ## Prestige and planet counts are on public leaderboard, so no FOW restrictions
    ## Per docs/ai/architecture/ai_architecture.adoc lines 279-300
    currentAct*: GameAct
    actStartTurn*: int

    # Act 2 tracking: Snapshot top 3 houses at Act 2 start (90% colonization)
    act2TopThreeHouses*: seq[HouseId]
    act2TopThreePrestige*: seq[int]

    # Cached values for transition gates (diagnostics)
    lastColonizationPercent*: float
    lastTotalPrestige*: int

  GracePeriodTracker* = object
    ## Tracks grace periods for capacity enforcement
    ## Per FINAL_TURN_SEQUENCE.md Income Phase Step 5
    totalSquadronsExpiry*: int  # Turn when total squadron grace expires
    fighterCapacityExpiry*: Table[SystemId, int]  # Per-colony fighter grace

  GameState* = object
    gameId*: string
    turn*: int
    phase*: GamePhase
    starMap*: StarMap
    houses*: Table[HouseId, House]
    lastTurnReports*: Table[HouseId, TurnResolutionReport] # Transient data for diagnostics
    homeworlds*: Table[HouseId, SystemId]  # Track homeworld system per house
    colonies*: Table[SystemId, Colony]
    fleets*: Table[FleetId, Fleet]
    fleetOrders*: Table[FleetId, FleetOrder]  # Persistent fleet orders (continue until completed)
    activeSpyMissions*: Table[FleetId, ActiveSpyMission]  # Active spy missions (fleet-based system)
    arrivedFleets*: Table[FleetId, SystemId]  # Fleets that arrived at order targets (checked in Conflict/Income phase)
    standingOrders*: Table[FleetId, StandingOrder]  # Standing orders (execute when no explicit order)
    turnDeadline*: int64          # Unix timestamp
    ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
    scoutLossEvents*: seq[intel_types.ScoutLossEvent]  # Scout losses for diplomatic processing
    populationInTransit*: seq[pop_types.PopulationInTransit]  # Space Guild population transfers in progress
    pendingProposals*: seq[dip_proposals.PendingProposal]  # Pending diplomatic proposals
    pendingMilitaryCommissions*: seq[econ_types.CompletedProject]  # Military units awaiting commissioning in next Command Phase
    pendingPlanetaryCommissions*: seq[econ_types.CompletedProject]  # Unused - planetary assets commission immediately in Maintenance Phase
    gracePeriodTimers*: Table[HouseId, GracePeriodTracker]  # Grace period tracking for capacity enforcement
    actProgression*: ActProgressionState  # Dynamic game act progression (global, public info)

    # Persistent reverse indices (DoD optimization for O(1) lookups)
    fleetsByLocation*: Table[SystemId, seq[FleetId]]
    fleetsByOwner*: Table[HouseId, seq[FleetId]]
    coloniesByOwner*: Table[HouseId, seq[SystemId]]
