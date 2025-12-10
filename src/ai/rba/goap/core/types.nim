## GOAP Core Types
##
## Foundation types for Goal-Oriented Action Planning system.
## Integrates with existing RBA as strategic planning layer.
##
## Architecture:
## ```
## Strategic Layer (GOAP):  Goals → A* Planning → Action Sequences
##                                      ↓
## Tactical Layer (RBA):   Requirements → Mediation → Execution
## ```
##
## Key Principles:
## - DRY: Shared types reused across all 4 domains (fleet, build, research, diplomatic)
## - Immutable: WorldStateSnapshot is value type (no mutation during planning)
## - Clean Integration: Uses FilteredGameState (fog-of-war compliant)

import std/[tables, options]
import ../../../../common/types/[core, tech, diplomacy, units]
import ../../../../engine/resolution/types as event_types # For EspionageAction

# =============================================================================
# World State Snapshot (Immutable Planning State)
# =============================================================================

type
  WorldStateSnapshot* = object
    ## Immutable snapshot of game state for GOAP planning
    ## Created from FilteredGameState (respects fog-of-war)
    ##
    ## NOTE: This is a planning-time abstraction. Real execution uses GameState.
    turn*: int
    houseId*: HouseId

    # Economic state
    treasury*: int              ## Available PP
    production*: int            ## Total colony production
    maintenanceCost*: int       ## Per-turn maintenance
    netIncome*: int             ## production - maintenance

    # Military state
    totalFleetStrength*: int    ## Sum of all fleet CER
    idleFleets*: seq[FleetId]   ## Fleets without orders
    fleetsUnderThreat*: seq[tuple[fleetId: FleetId, threatLevel: int]]

    # Territory state
    ownedColonies*: seq[SystemId]           ## All owned colonies
    vulnerableColonies*: seq[SystemId]      ## High-value, weak defense
    undefendedColonies*: seq[SystemId]      ## Zero defense

    # Strategic intelligence
    knownEnemyColonies*: seq[tuple[systemId: SystemId, owner: HouseId]]
    invasionOpportunities*: seq[SystemId]   ## Weak enemy colonies
    undefendedEnemyColonies*: seq[tuple[systemId: SystemId, owner: HouseId]] ## Enemy colonies with 0 ground/orbital defense
    diplomaticRelations*: Table[HouseId, DiplomaticState]

    # Tech state
    techLevels*: Table[TechField, int]
    researchProgress*: Table[TechField, int]  ## Current RP accumulated
    criticalTechGaps*: seq[TechField]          ## Behind enemies

    # Intelligence gaps
    # --- Territory state additions ---
    homeworld*: SystemId                    ## The AI's homeworld system ID
    totalColonies*: int                     ## Total number of colonies owned
    totalIU*: int                           ## Total industrial units across all colonies
    fleetsAtSystem*: Table[SystemId, seq[FleetIntel]] ## All known fleets at specific systems (own + enemy intel)

    # --- Strategic intelligence ---
    knownEnemyColonies*: seq[tuple[systemId: SystemId, owner: HouseId]]
    invasionOpportunities*: seq[SystemId]   ## Weak enemy colonies
    diplomaticRelations*: Table[HouseId, DiplomaticState]

    # --- Tech state ---
    techLevels*: Table[TechField, int]
    researchProgress*: Table[TechField, int]  ## Current RP accumulated
    criticalTechGaps*: seq[TechField]          ## Behind enemies

    # --- Intelligence gaps ---
    # --- Territory state additions ---
    homeworld*: SystemId                    ## The AI's homeworld system ID
    totalColonies*: int                     ## Total number of colonies owned
    totalIU*: int                           ## Total industrial units across all colonies
    fleetsAtSystem*: Table[SystemId, seq[FleetIntel]] ## All known fleets at specific systems (own + enemy intel)

    # --- Strategic intelligence ---
    knownEnemyColonies*: seq[tuple[systemId: SystemId, owner: HouseId]]
    invasionOpportunities*: seq[SystemId]   ## Weak enemy colonies
    diplomaticRelations*: Table[HouseId, DiplomaticState]

    # --- Tech state ---
    techLevels*: Table[TechField, int]
    researchProgress*: Table[TechField, int]  ## Current RP accumulated
    criticalTechGaps*: seq[TechField]          ## Behind enemies

    # --- Intelligence gaps ---
    staleIntelSystems*: seq[SystemId]       ## Need reconnaissance
    espionageTargets*: seq[HouseId]         ## High-value spy targets

# =============================================================================
# Goal System (What to Achieve)
# =============================================================================

type
  GoalType* {.pure.} = enum
    ## Strategic goals across all 6 domains
    # Fleet domain goals (Domestikos)
    DefendColony              ## Establish defensive fleet presence
    SecureSystem              ## Capture and hold system
    InvadeColony              ## Conquer enemy colony
    EliminateFleet            ## Destroy enemy fleet
    EstablishFleetPresence    ## Position fleet for strategic control
    ConductReconnaissance     ## Scout system for intelligence
    # Build domain goals (Domestikos)
    EstablishShipyard         ## Build shipyard for fleet production
    BuildFleet                ## Construct specific fleet composition
    ConstructStarbase         ## Build starbase for defense
    ExpandProduction          ## Increase colony output
    CreateInvasionForce       ## Build transports + marines
    EnsureRepairCapacity      ## Build drydocks or increase repair capacity
    # Research domain goals (Logothete)
    AchieveTechLevel          ## Reach specific tech level
    CloseResearchGap          ## Match enemy tech
    UnlockCapability          ## Enable ship/building construction
    # Diplomatic domain goals (Protostrator)
    SecureAlliance            ## Form alliance with house
    DeclareWar                ## Declare war on house
    ImproveRelations          ## Increase diplomatic standing
    IsolateEnemy              ## Turn other houses against target
    # Espionage domain goals (Drungarius - 10 espionage actions from diplomacy.md 8.2)
    GatherIntelligence        ## Scout reconnaissance (SpyPlanet, SpySystem, HackStarbase)
    StealTechnology           ## Tech Theft (steal 10 SRP)
    SabotageEconomy           ## Low/High Impact Sabotage (destroy 1d6 or 1d20 IU)
    AssassinateLeader         ## Assassination (reduce SRP gain by 50% for 1 turn)
    DisruptEconomy            ## Economic Manipulation (halve NCV for 1 turn)
    PropagandaCampaign        ## Psyops (reduce tax revenue by 25% for 1 turn)
    CyberAttack               ## Cyber Attack (cripple starbase)
    CounterIntelSweep         ## Counter-Intelligence Sweep (block enemy intel for 1 turn)
    StealIntelligence         ## Intelligence Theft (steal entire intel database)
    PlantDisinformation       ## Plant Disinformation (corrupt enemy intel 20-40% for 2 turns)
    EstablishIntelNetwork     ## Build EBP/CIP capability
    MaintainPrestige          ## Avoid penalties, improve diplomatic standing
    # Endgame/Elimination Goals (Gap 7)
    AchieveTotalVictory       ## Eliminate all remaining opponents
    LastStandReconquest       ## Recapture a colony after losing all

    # Economic domain goals (Eparch)
    TransferPopulation        ## Move population between colonies via Space Guild
    TerraformPlanet           ## Improve planet class
    DevelopInfrastructure     ## Build IU/facilities
    BalanceEconomy            ## Optimize colony production

  Goal* = object
    ## A desired state to achieve through planning
    goalType*: GoalType
    priority*: float           ## 0.0-1.0, higher = more urgent (from RBA requirement priority)
    target*: Option[SystemId]  ## For location-based goals
    targetHouse*: Option[HouseId]  ## For diplomatic/military goals
    requiredResources*: int    ## Estimated PP cost (updated during planning)
    deadline*: Option[int]     ## Turn by which goal must be achieved (optional)
    preconditions*: seq[PreconditionRef]  ## Must be true before planning
    successCondition*: SuccessConditionRef  ## Goal achieved when true
    description*: string       ## For logging/debugging. Can be auto-generated or manual.

  PreconditionRef* = ref object
    ## Reference to shared precondition (DRY: defined once in conditions.nim)
    conditionId*: string       ## Unique identifier (e.g., "HasMinBudget")
    params*: Table[string, int]  ## Parameters (e.g., minBudget=200)

  SuccessConditionRef* = ref object
    ## Reference to shared success condition (DRY: defined once in conditions.nim)
    conditionId*: string
    params*: Table[string, int]

# =============================================================================
# Action System (How to Achieve Goals)
# =============================================================================

type
  ActionType* {.pure.} = enum
    ## Concrete actions across all 6 domains
    # Fleet actions (Domestikos)
    MoveFleet                 ## Move fleet to system
    AssembleInvasionForce     ## Coordinate multiple fleets
    AttackColony              ## Execute invasion
    EstablishDefense          ## Assign guard duty
    ConductScoutMission       ## Reconnaissance operation
    # Build actions (Domestikos)
    ConstructShips            ## Build ships at colony
    BuildFacility             ## Construct infrastructure
    UpgradeInfrastructure     ## Increase IU
    # Research actions (Logothete)
    AllocateResearch          ## Invest RP in tech field
    PrioritizeTech            ## Shift research focus
    # Diplomatic actions (Protostrator)
    ProposeAlliance           ## Offer pact
    DeclareHostility          ## Break relations
    SendTribute               ## Buy goodwill
    # Espionage actions (Drungarius - 10 actions from diplomacy.md 8.2)
    SpyOnPlanet               ## Gather colony intelligence (basic recon)
    SpyOnSystem               ## Scout system for fleets (basic recon)
    HackStarbase              ## Steal tech/production data (basic recon)
    TechTheft                 ## Tech Theft (5 EBP, steal 10 SRP)
    SabotageLowImpact         ## Low Impact Sabotage (2 EBP, destroy 1d6 IU)
    SabotageHighImpact        ## High Impact Sabotage (7 EBP, destroy 1d20 IU)
    AssassinationOp           ## Assassination (10 EBP, reduce SRP gain 50% for 1 turn)
    EconomicManipulation      ## Economic Manipulation (6 EBP, halve NCV for 1 turn)
    PsyopsCampaign            ## Psyops Campaign (3 EBP, reduce tax 25% for 1 turn)
    CyberAttackOp             ## Cyber Attack (6 EBP, cripple starbase)
    CounterIntelSweepOp       ## Counter-Intel Sweep (4 EBP, block enemy intel 1 turn)
    IntelligenceTheftOp       ## Intelligence Theft (8 EBP, steal entire intel database)
    PlantDisinformationOp     ## Plant Disinformation (6 EBP, corrupt enemy intel 20-40% for 2 turns)
    InvestEBP                 ## Increase espionage budget points (40 PP per EBP)
    InvestCIP                 ## Increase counter-intel points
    # Economic actions (Eparch)
    TransferPopulationPTU     ## Order Space Guild population transfer
    InvestIU                  ## Industrial development
    TerraformOrder            ## Planetary development
    BuildColonyFacility       ## Construct colony infrastructure

  Action* = object
    ## A concrete step toward goal achievement
    actionType*: ActionType
    cost*: int                 ## PP cost
    duration*: int             ## Turns to complete
    target*: Option[SystemId]
    targetHouse*: Option[HouseId]
    shipClass*: Option[ShipClass]
    quantity*: int
    techField*: Option[TechField]
    preconditions*: seq[PreconditionRef]
    effects*: seq[EffectRef]
    description*: string

  EffectRef* = ref object
    ## Reference to shared effect definition (DRY: defined once in effects.nim)
    effectId*: string
    params*: Table[string, int]

# =============================================================================
# Plan System (Action Sequence to Goal)
# =============================================================================

type
  GOAPlan* = object
    ## A validated sequence of actions to achieve a goal
    goal*: Goal
    actions*: seq[Action]
    totalCost*: int            ## Sum of action costs
    estimatedTurns*: int       ## Total duration
    confidence*: float         ## 0.0-1.0, how likely to succeed
    dependencies*: seq[Goal]   ## Other goals that must complete first

  GOAPlanSet* = object
    ## Collection of plans for a turn
    plans*: seq[GOAPlan]
    multiTurnOps*: seq[GOAPlan]  ## Plans requiring >1 turn
    totalEstimatedCost*: int

# =============================================================================
# Configuration
# =============================================================================

import ../../config # Import GOAPConfig from the centralized RBA config
# No GOAPConfig definition here, as it's imported from config.nim

# =============================================================================
# Helper Functions
# =============================================================================

proc `$`*(goal: Goal): string =
  ## String representation for logging
  result = $goal.goalType
  if goal.target.isSome:
    result.add(" @ " & $goal.target.get())
  if goal.targetHouse.isSome:
    result.add(" vs " & $goal.targetHouse.get())

proc `$`*(action: Action): string =
  ## String representation for logging
  result = $action.actionType
  if action.quantity > 0:
    result.add(" x" & $action.quantity)
  if action.cost > 0:
    result.add(" (" & $action.cost & " PP)")
