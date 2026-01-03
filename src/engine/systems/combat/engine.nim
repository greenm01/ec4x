## EC4X Combat Engine - Main Entry Point
##
## Complete combat resolution system integrating all phases,
## damage, retreat, and termination logic.
##
## Pure game logic - no I/O, works with typed data

import std/[options, sequtils, strutils, random]
import ../../types/[core, combat as combat_types, game_state, squadron, ship]
import ../../state/engine
import ../../globals
import cer, resolution, retreat, damage, targeting
import ../squadron/entity
import ../../intel/detection

export combat_types

## Main Combat Resolution

proc resolveCombat*(state: GameState, context: BattleContext): CombatResult =
  ## Resolve complete combat scenario
  ## Pure function: same input = same output (deterministic PRNG)
  ##
  ## Returns full CombatResult with round-by-round details

  result = CombatResult(
    systemId: context.systemId,
    rounds: @[],
    survivors: @[],
    retreated: @[],
    eliminated: @[],
    victor: none(HouseId),
    totalRounds: 0,
    wasStalemate: false,
  )

  # Initialize RNG
  var rng = initRNG(context.seed)

  # Working copy of Task Forces
  var taskForces = context.taskForces

  # The actual diplomatic state checks happen in conflict_phase.nim before calling resolveCombat.
  # So, for the purpose of the combat engine's internal logic, we assume all provided TFs are hostile to each other
  # or their hostility is determined by their diplomatic status.

  # PRE-COMBAT DETECTION PHASE (Section 7.3.1.1)
  # Scouts and Starbases attempt to detect cloaked Raiders before combat begins
  # If detected, Raiders lose ambush advantage and attack in Phase 3 instead

  # Create std/random Rand from CombatRNG state for detection system
  # Detection uses std/random.Rand, combat uses CombatRNG
  # Cast uint64 to int64 to avoid range errors
  var detectionRng = initRand(cast[int64](rng.state))

  # Mark pre-detected houses as detected
  for targetIdx, targetTF in taskForces.mpairs:
    if targetTF.houseId in context.preDetectedHouses:
      taskForces[targetIdx].isCloaked = false

  for detectorIdx, detectorTF in taskForces.mpairs:
    # Skip if this task force has no ELI capability (no scouts)
    let detectorSquadronIds = detectorTF.squadrons.mapIt(it.squadronId)
    if not hasELICapability(state, detectorSquadronIds):
      continue

    # Check each opposing task force for cloaked raiders
    for targetIdx, targetTF in taskForces.mpairs:
      # Skip self and non-cloaked task forces
      if detectorIdx == targetIdx or not targetTF.isCloaked:
        continue

      # Diplomatic relations are assumed to be hostile at this point,
      # as combat task forces are assembled based on conflict_phase.nim's checks.
      # No further diplomatic checks needed within the combat engine's detection phase.

      # Raider detection uses simplified opposed rolls (assets.md:2.4.3)
      # Attacker: 1d10 + CLK vs Defender: 1d10 + ELI + starbaseBonus

      # Check if detector has scouts (required for detection)
      var hasScouts = false
      for sq in detectorTF.squadrons:
        let squadronOpt = state.squadron(sq.squadronId)
        if squadronOpt.isSome:
          let squadron = squadronOpt.get()
          if state.scoutShips(squadron).len > 0:
            hasScouts = true
            break

      # Check for starbase presence (provides +2 detection bonus)
      let starbaseBonus =
        if context.hasDefenderStarbase:
          gameConfig.combat.starbase.starbaseDetectionBonus
        else:
          0

      # Use target's house CLK level
      let targetCloakLevel = targetTF.clkLevel

      if targetCloakLevel > 0 and hasScouts:
        # Attempt detection with opposed rolls
        let detectionResult = detectRaider(
          targetCloakLevel, # Attacker's CLK
          detectorTF.eliLevel, # Defender's ELI
          starbaseBonus, # +2 if starbase present, else 0
          detectionRng,
        )

        when defined(debugDetection):
          logDebug(
            "Detection",
            "Raider detection attempt (opposed rolls)",
            "detector=",
            $detectorTF.houseId,
            " defenderELI=",
            $detectorTF.eliLevel,
            " target=",
            $targetTF.houseId,
            " attackerCLK=",
            $targetCloakLevel,
            " defenderRoll=",
            $detectionResult.roll,
            " attackerRoll=",
            $detectionResult.threshold,
            " detected=",
            $detectionResult.detected,
          )

        if detectionResult.detected:
          # Raiders detected! Remove ambush advantage
          taskForces[targetIdx].isCloaked = false

  # Track stalemate
  var consecutiveRoundsNoChange = 0

  # Combat loop
  for roundNum in 1 .. context.maxRounds:
    result.totalRounds = roundNum

    # Check combat termination before round
    let termCheck = checkCombatTermination(taskForces, consecutiveRoundsNoChange)
    if termCheck.shouldEnd:
      result.victor = termCheck.victor
      if termCheck.reason.contains("Stalemate"):
        result.wasStalemate = true
      break

    # Resolve all three combat phases
    let roundResults = resolveRound(
      taskForces,
      roundNum,
      context.diplomaticRelations,
      context.systemOwner,
      rng,
      desperationBonus = 0,
      allowAmbush = context.allowAmbush,
      allowStarbaseCombat = context.allowStarbaseCombat,
    )

    result.rounds.add(roundResults)

    # Check for progress
    var hasProgress = false
    for phaseResult in roundResults:
      if phaseResult.stateChanges.len > 0:
        hasProgress = true
        break

    if hasProgress:
      consecutiveRoundsNoChange = 0
    else:
      consecutiveRoundsNoChange += 1

    # Desperation mechanics: After 5 rounds without progress, give one final chance
    if consecutiveRoundsNoChange == 5:
      # Desperation round: both sides get +2 CER bonus
      let desperationResults = resolveRound(
        taskForces,
        roundNum + 1, # Desperation is a bonus "round"
        context.diplomaticRelations,
        context.systemOwner,
        rng,
        desperationBonus = 2, # +2 CER to all attacks
        allowAmbush = context.allowAmbush,
        allowStarbaseCombat = context.allowStarbaseCombat,
      )

      result.rounds.add(desperationResults)
      result.totalRounds += 1

      # Check if desperation broke the stalemate
      var desperationProgress = false
      for phaseResult in desperationResults:
        if phaseResult.stateChanges.len > 0:
          desperationProgress = true
          break

      if desperationProgress:
        # Reset stalemate counter - combat continues
        consecutiveRoundsNoChange = 0
      else:
        # Still no progress - force tactical stalemate
        result.wasStalemate = true
        break

    # Evaluate retreat BEFORE checking termination (operations.md:7.3.4)
    # Retreat evaluation happens after round completes but before termination check
    # This allows fleets to retreat before being eliminated

    # Can't retreat on first round
    if roundNum > 1:
      # Evaluate retreat for all Task Forces
      var retreatEvals: seq[RetreatEvaluation] = @[]
      for tf in taskForces:
        # Use prestige from game state (placeholder: use ROE * 10)
        let prestige = tf.roe * 10
        let eval = evaluateRetreat(tf, taskForces, prestige)
        if eval.wantsToRetreat:
          retreatEvals.add(eval)

      if retreatEvals.len > 0:
        # Get retreat priority order
        let retreatOrder = getRetreatPriority(taskForces)

        # Process retreats in priority order
        for houseId in retreatOrder:
          # Check if this house wants to retreat
          var wantsRetreat = false
          for eval in retreatEvals:
            if eval.taskForceHouse == houseId:
              wantsRetreat = true
              break

          if not wantsRetreat:
            continue

          # Execute retreat
          result.retreated.add(houseId)
          executeRetreat(taskForces, houseId)

          # After each retreat, remaining forces re-evaluate
          # (simplified: would check if retreat still desired)

    # Check combat termination after retreat evaluation
    let termCheck2 = checkCombatTermination(taskForces, consecutiveRoundsNoChange)
    if termCheck2.shouldEnd:
      result.victor = termCheck2.victor
      if termCheck2.reason.contains("Stalemate"):
        result.wasStalemate = true
      break

  # Record survivors and eliminated
  for tf in context.taskForces:
    let stillPresent = taskForces.anyIt(it.houseId == tf.houseId)
    if stillPresent:
      # Find updated Task Force
      for updatedTF in taskForces:
        if updatedTF.houseId == tf.houseId:
          result.survivors.add(updatedTF)
          break
    else:
      # Check if retreated or eliminated
      if not result.retreated.contains(tf.houseId):
        result.eliminated.add(tf.houseId)

  # If only survivors remain and no victor set, award to survivor
  if result.victor.isNone() and result.survivors.len == 1:
    result.victor = some(result.survivors[0].houseId)

## CombatSquadron Helper Methods

proc isAlive*(sq: CombatSquadron): bool {.inline.} =
  ## Check if squadron can still fight
  sq.state != CombatState.Destroyed

proc getCurrentAS*(sq: CombatSquadron): int32 {.inline.} =
  ## Get current attack strength (halved if crippled)
  if sq.state == CombatState.Crippled:
    max(1'i32, sq.attackStrength div 2)
  else:
    sq.attackStrength

proc resetRoundDamage*(sq: var CombatSquadron) {.inline.} =
  ## Reset damage counter for new round
  sq.damageThisTurn = 0

## Combat Initialization Helpers

proc classifyBucket(squadron: Squadron): TargetBucket =
  ## Classify squadron into combat bucket based on squadron class
  ## See docs/specs/07-combat.md for bucket definitions
  case squadron.squadronType
  of SquadronClass.Intel:
    TargetBucket.Raider  # Scouts = Raiders for targeting purposes
  of SquadronClass.Fighter:
    TargetBucket.Fighter
  of SquadronClass.Combat:
    # Combat squadrons are either Capital or Escort based on flagship
    # For now, default to Capital (can be refined with flagship class check)
    TargetBucket.Capital
  of SquadronClass.Auxiliary, SquadronClass.Expansion:
    TargetBucket.Escort  # Support squadrons treated as escorts

proc calculateTargetWeight(sq: CombatSquadron): float32 =
  ## Calculate target priority weight for targeting system
  ## Higher weight = higher priority target
  ## Formula: (AS / DS) * bucket_modifier

  # Avoid division by zero
  let defenseFactor = if sq.defenseStrength > 0:
    float32(sq.defenseStrength)
  else:
    1.0'f32

  # Base weight: attack strength divided by defense (threat-to-vulnerability ratio)
  var weight = float32(sq.attackStrength) / defenseFactor

  # Apply bucket-specific modifiers
  case sq.bucket
  of TargetBucket.Raider:
    weight *= 1.5'f32  # High priority - eliminate scouts/raiders first
  of TargetBucket.Capital:
    weight *= 1.2'f32  # High priority - major threats
  of TargetBucket.Escort:
    weight *= 1.0'f32  # Normal priority
  of TargetBucket.Fighter:
    weight *= 0.8'f32  # Lower priority - dealt with in fighter phase
  of TargetBucket.Starbase:
    weight *= 2.0'f32  # Highest priority - eliminate defensive assets

  return weight

proc initializeCombatSquadron*(state: GameState, squadron: Squadron): CombatSquadron =
  ## Convert Squadron to CombatSquadron for battle
  ## Cache total attack/defense/command stats from all ships in squadron
  let flagship = state.ship(squadron.flagshipId).get()

  # Calculate total squadron strength (all ships)
  let totalAS = int32(state.combatStrength(squadron))
  let totalDS = int32(state.defenseStrength(squadron))

  # Look up CR from flagship ship class config
  let flagshipCR = gameConfig.ships.ships[flagship.shipClass].commandRating

  result = CombatSquadron(
    squadronId: squadron.id,
    attackStrength: totalAS,
    defenseStrength: totalDS,
    commandRating: flagshipCR,  # CR comes from flagship class config
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: classifyBucket(squadron),
    targetWeight: 0.0,
  )

  # Calculate initial target weight
  result.targetWeight = calculateTargetWeight(result)

proc initializeTaskForce*(
    state: GameState,
    house: HouseId,
    squadrons: seq[Squadron],
    roe: int,
    prestige: int = 50,
    isHomeworld: bool = false,
): TaskForce =
  ## Create Task Force from squadrons
  ##
  ## Args:
  ##   state: GameState for entity lookups
  ##   house: House ID
  ##   squadrons: Squadrons in Task Force
  ##   roe: Rules of Engagement (0-10)
  ##   prestige: House prestige for morale (default 50)
  ##   isHomeworld: Defending homeworld (never retreat)

  # Look up house tech levels
  let houseData = state.house(house).get()
  let eliLevel = houseData.techTree.levels.eli
  let clkLevel = houseData.techTree.levels.clk

  result = TaskForce(
    houseId: house,
    squadrons: @[],
    facilities: @[],
    roe: int32(roe),
    isCloaked: false,
    moraleModifier: 0,
    isDefendingHomeworld: isHomeworld,
    eliLevel: eliLevel,
    clkLevel: clkLevel,
  )

  # Convert squadrons
  for sq in squadrons:
    result.squadrons.add(initializeCombatSquadron(state, sq))

  # Check if all squadrons are cloaked Raiders
  var allCloaked = true
  var hasRaiders = false
  for sq in squadrons:
    if state.raiderShips(sq).len > 0:
      hasRaiders = true
      if not state.isCloaked(sq):
        allCloaked = false
    else:
      allCloaked = false

  result.isCloaked = hasRaiders and allCloaked

  # Calculate morale modifier from prestige
  result.moraleModifier = int32(getMoraleROEModifier(prestige))

## Quick Battle Helper

proc quickBattle*(
    state: GameState,
    attacker: TaskForce,
    defender: TaskForce,
    systemId: SystemId = SystemId(0),
    seed: int64 = 12345,
): CombatResult =
  ## Convenience function for simple 1v1 battles
  let context = BattleContext(
    systemId: systemId, taskForces: @[attacker, defender], seed: seed, maxRounds: 20
  )

  return resolveCombat(state, context)
