## Fleet order types shared between modules
## Created to avoid circular dependencies between gamestate and orders modules

import std/options
import ../common/types/[core, planets]

type
  FleetOrderType* {.pure.} = enum
    Hold              # Hold position, do nothing
    Move              # Navigate to target system
    SeekHome          # Find closest friendly system
    Patrol            # Defend and intercept in system
    GuardStarbase     # Protect orbital installation
    GuardPlanet       # Planetary defense
    BlockadePlanet    # Planetary siege
    Bombard           # Orbital bombardment
    Invade              # Ground assault
    Blitz               # Combined bombardment + invasion
    Colonize          # Establish colony
    SpyPlanet         # Intelligence gathering on planet
    SpySystem         # Reconnaissance of system
    HackStarbase      # Electronic warfare
    JoinFleet         # Merge with another fleet (scouts gain mesh network ELI bonus)
    Rendezvous        # Meet with other spy scouts/fleets at location
    Salvage           # Recover wreckage
    Reserve           # Place fleet on reserve status (50% maint, half AS/DS, can't move)
    Mothball          # Mothball fleet (0% maint, offline, screened in combat)
    Reactivate        # Return reserve/mothballed fleet to active duty
    ViewWorld         # Long-range planetary reconnaissance (Order 19)

  FleetOrder* = object
    ## Persistent fleet order that continues until completed or overridden
    fleetId*: FleetId
    orderType*: FleetOrderType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int  # Execution order within turn

proc isThreateningFleetOrder*(orderType: FleetOrderType): bool =
  ## Returns true if the order immediately escalates to Enemy status.
  ## Per docs/engine/mechanics/diplomatic-combat-resolution.md Section 3.1
  case orderType
  of FleetOrderType.BlockadePlanet, FleetOrderType.Bombard, FleetOrderType.Invade,
     FleetOrderType.Blitz, FleetOrderType.HackStarbase:
    true
  else:
    false

proc isNonThreateningButProvocativeFleetOrder*(orderType: FleetOrderType): bool =
  ## Returns true if the order escalates Neutral->Hostile on first offense,
  ## and Hostile->Enemy on second offense.
  ## Per docs/engine/mechanics/diplomatic-combat-resolution.md Section 3.2
  case orderType
  of FleetOrderType.Hold, FleetOrderType.Patrol, FleetOrderType.SpyPlanet,
     FleetOrderType.SpySystem, FleetOrderType.ViewWorld, FleetOrderType.Salvage,
     FleetOrderType.JoinFleet, FleetOrderType.Rendezvous:
    true
  else:
    false

  # =============================================================================
  # Standing Orders - Persistent Fleet Behaviors
  # =============================================================================

  StandingOrderType* {.pure.} = enum
    ## Persistent fleet behaviors that execute when no explicit order given
    ## Reduces micromanagement, provides quality-of-life for players and AI
    ## See docs/architecture/standing-orders.md for complete design
    None              # No standing order (default)
    PatrolRoute       # Follow patrol path indefinitely
    DefendSystem      # Guard system, engage hostile forces per ROE
    AutoColonize      # ETACs auto-colonize nearest suitable system
    AutoReinforce     # Join nearest friendly fleet when damaged
    AutoRepair        # Return to nearest shipyard when HP < threshold
    AutoEvade         # Fall back to safe system if outnumbered per ROE
    GuardColony       # Defend specific colony system
    BlockadeTarget    # Maintain blockade on enemy colony

  StandingOrderParams* = object
    ## Parameters for standing order execution
    ## Different parameters for different order types
    case orderType*: StandingOrderType
    of PatrolRoute:
      patrolSystems*: seq[SystemId]     # Patrol path (loops)
      patrolIndex*: int                 # Current position in path
    of DefendSystem, GuardColony:
      defendTargetSystem*: SystemId     # System to defend
      defendMaxRange*: int              # Max distance from target (jumps)
    of AutoColonize:
      preferredPlanetClasses*: seq[PlanetClass]  # Priority classes
      colonizeMaxRange*: int            # Max colonization distance
    of AutoReinforce:
      reinforceDamageThreshold*: float  # HP% to trigger (e.g., 0.5 = 50%)
      targetFleet*: Option[FleetId]     # Specific fleet, or nearest
    of AutoRepair:
      repairDamageThreshold*: float     # HP% to trigger
      targetShipyard*: Option[SystemId] # Specific shipyard, or nearest
    of AutoEvade:
      fallbackSystem*: SystemId         # Safe retreat destination
      evadeTriggerRatio*: float         # Strength ratio to retreat
    of BlockadeTarget:
      blockadeTargetColony*: SystemId   # Colony to blockade
    else:
      discard

  StandingOrder* = object
    ## Complete standing order specification
    ## Stored in GameState.standingOrders: Table[FleetId, StandingOrder]
    fleetId*: FleetId
    orderType*: StandingOrderType
    params*: StandingOrderParams
    roe*: int                          # Rules of Engagement (0-10)
    createdTurn*: int                  # When order was issued
    lastExecutedTurn*: int             # Last turn this executed
    executionCount*: int               # Times executed
    suspended*: bool                   # Temporarily disabled (explicit order override)
    enabled*: bool                     # Per-fleet toggle (player control)
    activationDelayTurns*: int         # Grace period before activation after order completion
    turnsUntilActivation*: int         # Countdown: decrements each turn without explicit order

  # =============================================================================
  # Colony Management Orders
  # =============================================================================

  ColonyManagementAction* {.pure.} = enum
    ## Colony-level management actions for player control
    SetTaxRate        # Adjust colony tax rate (0-100)
    SetAutoRepair     # Toggle automatic repair submission

  ColonyManagementOrder* = object
    ## Colony management order specification
    colonyId*: SystemId
    action*: ColonyManagementAction
    # Parameters depend on action type
    taxRate*: int                # For SetTaxRate (0-100)
    enableAutoRepair*: bool      # For SetAutoRepair (true/false)

# =============================================================================
# Fleet Order Categorization (Phase-Based Execution)
# =============================================================================
# Per FINAL_TURN_SEQUENCE.md, different order types execute in different phases

proc isMovementOrder*(orderType: FleetOrderType): bool =
  ## Movement orders execute in Maintenance Phase
  ## Per FINAL_TURN_SEQUENCE.md: "Movement orders execute Turn N Maintenance Phase"
  result = orderType in {
    FleetOrderType.Hold,
    FleetOrderType.Move,
    FleetOrderType.SeekHome,
    FleetOrderType.Patrol
  }

proc isCombatOrder*(orderType: FleetOrderType): bool =
  ## Combat orders execute in Conflict Phase (next turn)
  ## Per FINAL_TURN_SEQUENCE.md: "Combat orders execute Turn N+1 Conflict Phase"
  result = orderType in {
    FleetOrderType.Bombard,
    FleetOrderType.Invade,
    FleetOrderType.Blitz,
    FleetOrderType.GuardStarbase,
    FleetOrderType.GuardPlanet,
    FleetOrderType.BlockadePlanet
  }

proc isAdministrativeOrder*(orderType: FleetOrderType): bool =
  ## Administrative orders execute in Command Phase
  ## These are immediate fleet management operations
  result = orderType in {
    FleetOrderType.JoinFleet,
    FleetOrderType.Rendezvous,
    FleetOrderType.Reserve,
    FleetOrderType.Mothball,
    FleetOrderType.Reactivate,
    FleetOrderType.ViewWorld
  }

proc isSpecialOrder*(orderType: FleetOrderType): bool =
  ## Special orders handled by specific phase systems
  ## - Colonize: Command Phase PART A (simultaneous resolution)
  ## - Salvage: Income Phase Step 4
  ## - Espionage: Conflict Phase (simultaneous resolution)
  result = orderType in {
    FleetOrderType.Colonize,      # Command Phase PART A
    FleetOrderType.Salvage,        # Income Phase Step 4
    FleetOrderType.SpyPlanet,      # Conflict Phase
    FleetOrderType.SpySystem,      # Conflict Phase
    FleetOrderType.HackStarbase    # Conflict Phase
  }
