## Turn Cycle Engine - Canonical Turn Resolution Orchestrator
##
## Coordinates the four-phase turn cycle per docs/engine/ec4x_canonical_turn_cycle.md
##
## **Phase Order:**
## 1. Conflict Phase (CON) - Combat, espionage, colonization
## 2. Income Phase (INC) - Economics, maintenance, victory checks
## 3. Command Phase (CMD) - Commissioning, player orders, validation
## 4. Production Phase (PRD) - Movement, construction, research
##
## **Key Timing Principle:**
## Commands submitted Turn N execute in phases of Turn N+1.
## Fleet travel (PRD) positions units for next turn's Conflict Phase.
##
## **Architecture:**
## - Uses UFCS pattern for state access
## - Phases mutate state in-place
## - Events collected across all phases
## - pendingCommissions passed from Production to next Command Phase

import std/[tables, random, strformat]
import ../../common/logger
import ../types/[
  core, game_state, command, event, combat, victory
]
import ./[conflict_phase, income_phase, command_phase, production_phase]
import ../victory/engine

type
  TurnResult* = object
    ## Result of turn resolution
    events*: seq[GameEvent]
    combatResults*: seq[CombatResult]
    victoryCheck*: VictoryCheck
    turnAdvanced*: bool

proc resolveTurn*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    rng: var Rand
): TurnResult =
  ## Execute complete turn cycle per canonical spec
  ##
  ## Args:
  ##   state: Game state to mutate in-place
  ##   orders: Command packets from all houses for this turn
  ##   rng: Random number generator for stochastic resolution
  ##
  ## Returns:
  ##   TurnResult with events and combat reports from all phases
  ##
  ## **Phase Execution Order:**
  ## 1. Conflict - Resolves combat from commands stored last turn
  ## 2. Income - Calculates economics, checks victory conditions
  ## 3. Command - Commissions assets, processes new player orders
  ## 4. Production - Moves fleets, advances construction, research

  logInfo("TurnCycle", &"=== Turn {state.turn} Resolution Begin ===")

  result.events = @[]
  result.combatResults = @[]
  result.victoryCheck = VictoryCheck(victoryOccurred: false)
  result.turnAdvanced = false

  # =========================================================================
  # PHASE 1: CONFLICT PHASE
  # =========================================================================
  # Resolves combat, espionage, and colonization for fleets that arrived
  # at their targets. Uses commands stored in Fleet.command from last turn.
  logInfo("TurnCycle", "[Phase 1/4] Conflict Phase")
  resolveConflictPhase(state, orders, result.combatResults, result.events, rng)

  # =========================================================================
  # PHASE 2: INCOME PHASE
  # =========================================================================
  # Calculates production, applies blockades, processes maintenance,
  # enforces capacity limits, collects resources, checks victory conditions.
  logInfo("TurnCycle", "[Phase 2/4] Income Phase")
  state.resolveIncomePhase(orders, result.events, rng)

  # Check victory conditions after Income Phase (INC10b)
  # Victory condition configuration - use defaults if not specified
  let victoryCondition = VictoryCondition(
    turnLimit: 100,  # Default turn limit
    enableDefensiveCollapse: true
  )
  result.victoryCheck = checkVictoryConditions(
    state, victoryCondition
  )
  
  if result.victoryCheck.victoryOccurred:
    logInfo("TurnCycle",
      &"Victory achieved: {result.victoryCheck.status.description}")
    # Still advance turn but skip remaining phases
    state.turn += 1
    result.turnAdvanced = true
    return result

  # =========================================================================
  # PHASE 3: COMMAND PHASE
  # =========================================================================
  # Commissions completed assets, processes auto-repair, colony automation,
  # then processes player-submitted orders for this turn.
  logInfo("TurnCycle", "[Phase 3/4] Command Phase")
  resolveCommandPhase(state, orders, result.events, rng)

  # =========================================================================
  # PHASE 4: PRODUCTION PHASE
  # =========================================================================
  # Moves fleets toward targets, advances construction/repair queues,
  # processes diplomatic actions, population transfers, terraforming,
  # and research advancement.
  logInfo("TurnCycle", "[Phase 4/4] Production Phase")
  let completedProjects = resolveProductionPhase(
    state, result.events, orders, rng
  )

  # Store completed military projects for next turn's Command Phase
  # Planetary defense already commissioned in Production Phase Step 2b
  # Ships will be commissioned at start of next turn's Command Phase CMD2
  state.pendingCommissions = completedProjects
  if completedProjects.len > 0:
    logInfo("TurnCycle",
      &"Stored {completedProjects.len} projects for next turn commissioning")

  # =========================================================================
  # TURN ADVANCEMENT
  # =========================================================================
  state.turn += 1
  result.turnAdvanced = true

  logInfo("TurnCycle", &"=== Turn {state.turn - 1} Resolution Complete ===")
  logInfo("TurnCycle",
    &"  Events: {result.events.len}, Combat Results: {result.combatResults.len}")

proc resolveTurnWithSeed*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    seed: int64
): TurnResult =
  ## Execute turn with specific RNG seed for reproducibility
  ##
  ## Useful for:
  ## - Deterministic testing
  ## - Replay functionality
  ## - Debug reproduction
  var rng = initRand(seed)
  result = resolveTurn(state, orders, rng)

proc resolveTurnDeterministic*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket]
): TurnResult =
  ## Execute turn with turn-number-based seed for deterministic replay
  ##
  ## Uses state.turn as seed, ensuring same results for same game state.
  ## Recommended for normal gameplay to enable replay/debugging.
  var rng = initRand(state.turn)
  result = resolveTurn(state, orders, rng)
