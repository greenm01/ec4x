## Turn Cycle Engine - Canonical Turn Resolution Orchestrator
##
## Coordinates the four-phase turn cycle per docs/engine/ec4x_canonical_turn_cycle.md
##
## **Phase Order:**
## 1. Conflict Phase (CON) - Combat, espionage, colonization
## 2. Income Phase (INC) - Economics, maintenance, victory checks
## 3. Command Phase (CMD) - Commissioning, player commands, validation
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
## - Player-facing turn N+1 state already includes any assets completed in
##   turn N Production

import std/[tables, random, strformat, options]
import ../../common/logger
import ../types/[
  core, game_state, command, event, combat, victory, production
]
import ../state/engine as state_engine
import ./[conflict_phase, income_phase, command_phase, production_phase]
import ../victory/engine
import ../systems/production/commissioning

proc commissionCompletedAssetsForPlayerTurn(
    state: GameState,
    completedProjects: seq[CompletedProject],
    events: var seq[GameEvent]
) =
  ## Publish-facing turn state should already include newly commissioned
  ## assets. Commission them after Production advancement and after the
  ## turn counter advances into the next player turn.
  if completedProjects.len == 0:
    return

  var militaryProjects: seq[CompletedProject] = @[]
  var planetaryProjects: seq[CompletedProject] = @[]

  for project in completedProjects:
    if project.projectType == BuildType.Ship:
      militaryProjects.add(project)
    else:
      planetaryProjects.add(project)

  if militaryProjects.len > 0:
    commissioning.commissionShips(state, militaryProjects, events)
  if planetaryProjects.len > 0:
    commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)

proc commissionCompletedRepairsForPlayerTurn(
    state: GameState,
    events: var seq[GameEvent]
) =
  var completedRepairs: seq[RepairProject] = @[]
  for (repairId, _) in state.repairProjects.entities.index.pairs:
    let repairOpt = state_engine.repairProject(state, repairId)
    if repairOpt.isSome:
      let repair = repairOpt.get()
      if repair.turnsRemaining <= 0:
        completedRepairs.add(repair)

  if completedRepairs.len > 0:
    commissioning.commissionRepairedShips(state, completedRepairs, events)

type
  TurnResult* = object
    ## Result of turn resolution
    events*: seq[GameEvent]
    combatResults*: seq[CombatResult]
    victoryCheck*: VictoryCheck
    turnAdvanced*: bool

proc resolveTurn*(
    state: GameState,
    commands: Table[HouseId, CommandPacket],
    rng: var Rand
): TurnResult =
  ## Execute complete turn cycle per canonical spec
  ##
  ## Args:
  ##   state: Game state to mutate in-place
  ##   commands: Command packets from all houses for this turn
  ##   rng: Random number generator for stochastic resolution
  ##
  ## Returns:
  ##   TurnResult with events and combat reports from all phases
  ##
  ## **Phase Execution Order:**
  ## 1. Conflict - Resolves combat from commands stored last turn
  ## 2. Income - Calculates economics, checks victory conditions
  ## 3. Command - Commissions assets, processes new player commands
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
  resolveConflictPhase(state, commands, result.combatResults, result.events, rng)

  # =========================================================================
  # PHASE 2: INCOME PHASE
  # =========================================================================
  # Calculates production, applies blockades, processes maintenance,
  # enforces capacity limits, collects resources, checks victory conditions.
  logInfo("TurnCycle", "[Phase 2/4] Income Phase")
  state.resolveIncomePhase(commands, result.events, rng)

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
    state.lastTurnEvents = result.events
    state.turn += 1
    result.turnAdvanced = true
    return result

  # =========================================================================
  # PHASE 3: COMMAND PHASE
  # =========================================================================
  # Commissions completed assets, processes auto-repair, colony automation,
  # then processes player-submitted commands for this turn.
  logInfo("TurnCycle", "[Phase 3/4] Command Phase")
  var mutableCommands = commands
  resolveCommandPhase(state, mutableCommands, result.events, rng)

  # =========================================================================
  # PHASE 4: PRODUCTION PHASE
  # =========================================================================
  # Moves fleets toward targets, advances construction/repair queues,
  # processes diplomatic actions, population transfers, terraforming,
  # and research advancement.
  logInfo("TurnCycle", "[Phase 4/4] Production Phase")
  let completedProjects = resolveProductionPhase(
    state, result.events, mutableCommands, rng
  )

  # =========================================================================
  # TURN ADVANCEMENT
  # =========================================================================
  state.turn += 1
  state.pendingCommissions = @[]
  state.commissionCompletedAssetsForPlayerTurn(completedProjects, result.events)
  state.commissionCompletedRepairsForPlayerTurn(result.events)

  # Store events for PlayerState creation (fog-of-war filtering per house)
  state.lastTurnEvents = result.events
  result.turnAdvanced = true

  logInfo("TurnCycle", &"=== Turn {state.turn - 1} Resolution Complete ===")
  logInfo("TurnCycle",
    &"  Events: {result.events.len}, Combat Results: {result.combatResults.len}")

proc resolveTurnWithSeed*(
    state: GameState,
    commands: Table[HouseId, CommandPacket],
    seed: int64
): TurnResult =
  ## Execute turn with specific RNG seed for reproducibility
  ##
  ## Useful for:
  ## - Deterministic testing
  ## - Replay functionality
  ## - Debug reproduction
  var rng = initRand(seed)
  result = resolveTurn(state, commands, rng)

proc resolveTurnDeterministic*(
    state: GameState,
    commands: Table[HouseId, CommandPacket]
): TurnResult =
  ## Execute turn with turn-number-based seed for deterministic replay
  ##
  ## Uses state.turn as seed, ensuring same results for same game state.
  ## Recommended for normal gameplay to enable replay/debugging.
  var rng = initRand(state.turn)
  result = resolveTurn(state, commands, rng)
