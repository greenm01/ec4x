import std/[tables, options, math, algorithm, logging]
import turn_cycle/[conflict_phase, income_phase, command_phase, production_phase]

proc executeTurnCycle*(state: var GameState, commands: Table[HouseId, CommandPacket]): TurnReport =
  # Canonical turn cycle
  conflict_phase.execute(state)
  income_phase.execute(state)
  state.turn += 1
  command_phase.execute(state, commands)
  production_phase.execute(state)
  
  generateTurnReport(state)

proc advanceTurn*(state: var GameState) =
  ## Advance to next strategic cycle
  state.turn += 1

proc initTurnResolutionReport*(): TurnResolutionReport =
  ## Initialize an empty report with default zero values.
  result = TurnResolutionReport()

proc getCurrentGameAct*(state: var GameState, config: ActProgressionConfig): GameAct =
  ## Determine and update current game act based on dynamic gates
  ##
  ## Dynamic 4-act strategic progression (game-state driven, not turn-based)
  ## Per docs/ai/architecture/ai_architecture.adoc lines 279-300
  ##
  ## Transition Gates:
  ## - Act 1 → Act 2: Map becomes ≥ config threshold % colonized (default 90%)
  ## - Act 2 → Act 3: Major power eliminated (top 3 house at Act 2 start)
  ## - Act 3 → Act 4: One house controls > config threshold % prestige (default 50%)
  ##
  ## Updates state.actProgression in-place during transitions
  ## Acts as state machine: only transitions forward, never backward
  ## Idempotent: can be called multiple times per turn safely

  # Calculate current metrics
  let totalSystems = state.starMap.systems.len
  let colonizedSystems = state.colonies.len
  let colonizationPercent = if totalSystems > 0:
    colonizedSystems.float / totalSystems.float
  else:
    0.0

  # Count total prestige across all active (non-eliminated) houses
  var totalPrestige = 0
  var maxPrestige = 0
  var maxPrestigeHouse: HouseId = "".HouseId
  for houseId, house in state.houses:
    if not house.eliminated:
      totalPrestige += house.prestige
      if house.prestige > maxPrestige:
        maxPrestige = house.prestige
        maxPrestigeHouse = houseId

  # Check progression gates and transition if needed
  case state.actProgression.currentAct
  of GameAct.Act1_LandGrab:
    # Act 1 → Act 2 Gate: Colonization threshold reached
    if colonizationPercent >= config.act1_to_act2_colonization_threshold:
      # Capture top 3 houses by prestige at Act 2 start
      var sortedHouses: seq[tuple[houseId: HouseId, prestige: int]] = @[]
      for houseId, house in state.houses:
        if not house.eliminated:
          sortedHouses.add((houseId, house.prestige))

      # Sort by prestige descending
      sortedHouses.sort(proc (a, b: auto): int = cmp(b.prestige, a.prestige))

      # Capture top 3 (or fewer if less than 3 houses remain)
      let top3Count = min(3, sortedHouses.len)
      state.actProgression.act2TopThreeHouses = @[]
      state.actProgression.act2TopThreePrestige = @[]
      for i in 0 ..< top3Count:
        state.actProgression.act2TopThreeHouses.add(sortedHouses[i].houseId)
        state.actProgression.act2TopThreePrestige.add(sortedHouses[i].prestige)

      # Transition to Act 2
      state.actProgression.currentAct = GameAct.Act2_RisingTensions
      state.actProgression.actStartTurn = state.turn

      info "Act progression: Transitioned to Act 2 (Rising Tensions) at turn ", state.turn,
           " (colonization: ", int(colonizationPercent * 100), "%)"
      debug "Act 2 top 3 powers: ", $state.actProgression.act2TopThreeHouses,
            " with prestige ", $state.actProgression.act2TopThreePrestige

  of GameAct.Act2_RisingTensions:
    # Act 2 → Act 3 Gate: Major power eliminated (any top-3 house from Act 2 start)
    for houseId in state.actProgression.act2TopThreeHouses:
      if state.houses.hasKey(houseId) and state.houses[houseId].eliminated:
        # Major power eliminated - transition to Act 3
        state.actProgression.currentAct = GameAct.Act3_TotalWar
        state.actProgression.actStartTurn = state.turn

        info "Act progression: Transitioned to Act 3 (Total War) at turn ", state.turn,
             " (major power eliminated: House ", houseId, ")"
        break

  of GameAct.Act3_TotalWar:
    # Act 3 → Act 4 Gate: Prestige dominance (>50% of total prestige)
    if totalPrestige > 0:
      let prestigePercent = maxPrestige.float / totalPrestige.float
      if prestigePercent > config.act3_to_act4_prestige_threshold:
        # Clear leader emerged - transition to Act 4
        state.actProgression.currentAct = GameAct.Act4_Endgame
        state.actProgression.actStartTurn = state.turn

        info "Act progression: Transitioned to Act 4 (Endgame) at turn ", state.turn,
             " (House ", maxPrestigeHouse, " controls ", int(prestigePercent * 100),
             "% of total prestige)"

  of GameAct.Act4_Endgame:
    # Already in final act, no further transitions
    discard

  # Update cached metrics for diagnostics
  state.actProgression.lastColonizationPercent = colonizationPercent
  state.actProgression.lastTotalPrestige = totalPrestige

  return state.actProgression.currentAct
