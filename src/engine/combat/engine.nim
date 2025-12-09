## EC4X Combat Engine - Main Entry Point
##
## Complete combat resolution system integrating all phases,
## damage, retreat, and termination logic.
##
## Pure game logic - no I/O, works with typed data

import std/[options, tables, sequtils, strutils, random]
import types, cer, resolution, retreat, damage, ../squadron
import ../intelligence/detection

export BattleContext, CombatResult, TaskForce, CombatSquadron

## Main Combat Resolution

proc resolveCombat*(context: BattleContext): CombatResult =
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
    wasStalemate: false
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
    if targetTF.house in context.preDetectedHouses:
      taskForces[targetIdx].isCloaked = false

  for detectorIdx, detectorTF in taskForces.mpairs:
    # Skip if this task force has no ELI capability (no scouts)
    let detectorSquadrons = detectorTF.squadrons.mapIt(it.squadron)
    if not hasELICapability(detectorSquadrons):
      continue

    # Check each opposing task force for cloaked raiders
    for targetIdx, targetTF in taskForces.mpairs:
      # Skip self and non-cloaked task forces
      if detectorIdx == targetIdx or not targetTF.isCloaked:
        continue

      # Check diplomatic relations - only detect enemies
      let dipState = diplomaticRelations.getOrDefault((detectorTF.house, targetTF.house), DiplomaticState.Enemy)
      if dipState != DiplomaticState.Enemy:
        continue

      # Create ELI unit using house ELI level, not ship stats
      # Count scouts for mesh network bonus
      var scoutCount = 0
      # TODO: Check if battle system has starbases (colony facilities, not squadrons)
      # Starbases moved to facility system - need colony data to determine presence
      var hasStarbase = false  # Placeholder - needs colony data integration
      for sq in detectorTF.squadrons:
        if sq.squadron.scoutShips().len > 0:
          scoutCount += sq.squadron.scoutShips().len

      # Build ELI levels array for mesh network calculation
      # All scouts have the house's ELI tech level
      var eliLevels: seq[int] = @[]
      for i in 0..<scoutCount:
        eliLevels.add(detectorTF.eliLevel)

      let detectorUnit = ELIUnit(
        eliLevels: eliLevels,
        isStarbase: hasStarbase
      )

      # Use target's house CLK level
      let targetCloakLevel = targetTF.clkLevel

      if targetCloakLevel > 0 and eliLevels.len > 0:
        # Attempt detection
        let detectionResult = detectRaider(detectorUnit, targetCloakLevel, detectionRng)

        when defined(debugDetection):
          logDebug("Detection", "Cloak detection attempt",
                  "detector=", $detectorTF.house, " detectorELI=", $detectorTF.eliLevel,
                  " scouts=", $scoutCount, " target=", $targetTF.house, " targetCLK=", $targetCloakLevel,
                  " effectiveELI=", $detectionResult.effectiveELI, " roll=", $detectionResult.roll,
                  " threshold=", $detectionResult.threshold, " detected=", $detectionResult.detected)

        if detectionResult.detected:
          # Raiders detected! Remove ambush advantage
          taskForces[targetIdx].isCloaked = false

  # Track stalemate
  var consecutiveRoundsNoChange = 0

  # Combat loop
  for roundNum in 1..context.maxRounds:
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
      rng,
      desperationBonus = 0,
      allowAmbush = context.allowAmbush,
      allowStarbaseCombat = context.allowStarbaseCombat
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
        roundNum + 1,  # Desperation is a bonus "round"
        rng,
        desperationBonus = 2,  # +2 CER to all attacks
        allowAmbush = context.allowAmbush,
        allowStarbaseCombat = context.allowStarbaseCombat
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
            if eval.taskForce == houseId:
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
    let stillPresent = taskForces.anyIt(it.house == tf.house)
    if stillPresent:
      # Find updated Task Force
      for updatedTF in taskForces:
        if updatedTF.house == tf.house:
          result.survivors.add(updatedTF)
          break
    else:
      # Check if retreated or eliminated
      if not result.retreated.contains(tf.house):
        result.eliminated.add(tf.house)

  # If only survivors remain and no victor set, award to survivor
  if result.victor.isNone() and result.survivors.len == 1:
    result.victor = some(result.survivors[0].house)

## Combat Initialization Helpers

proc initializeCombatSquadron*(squadron: Squadron): CombatSquadron =
  ## Convert Squadron to CombatSquadron for battle
  result = CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: classifyBucket(squadron),
    targetWeight: 0.0
  )

  # Calculate initial target weight
  result.targetWeight = calculateTargetWeight(result)

proc initializeTaskForce*(
  house: HouseId,
  squadrons: seq[Squadron],
  roe: int,
  prestige: int = 50,
  isHomeworld: bool = false,
  eliLevel: int = 1,
  clkLevel: int = 1
): TaskForce =
  ## Create Task Force from squadrons
  ##
  ## Args:
  ##   house: House ID
  ##   squadrons: Squadrons in Task Force
  ##   roe: Rules of Engagement (0-10)
  ##   prestige: House prestige for morale (default 50)
  ##   isHomeworld: Defending homeworld (never retreat)
  ##   eliLevel: House ELI tech level (for scout detection)
  ##   clkLevel: House CLK tech level (for raider cloaking)

  result = TaskForce(
    house: house,
    squadrons: @[],
    roe: roe,
    isCloaked: false,
    moraleModifier: 0,
    scoutBonus: false,
    isDefendingHomeworld: isHomeworld,
    eliLevel: eliLevel,
    clkLevel: clkLevel
  )

  # Convert squadrons
  for sq in squadrons:
    result.squadrons.add(initializeCombatSquadron(sq))

  # Check for scouts (ELI capability)
  for sq in squadrons:
    if sq.scoutShips().len > 0:
      result.scoutBonus = true
      break

  # Check if all squadrons are cloaked Raiders
  var allCloaked = true
  var hasRaiders = false
  for sq in squadrons:
    if sq.raiderShips().len > 0:
      hasRaiders = true
      if not sq.isCloaked():
        allCloaked = false
    else:
      allCloaked = false

  result.isCloaked = hasRaiders and allCloaked

  # Calculate morale modifier from prestige
  result.moraleModifier = getMoraleROEModifier(prestige)

## Quick Battle Helper

proc quickBattle*(
  attacker: TaskForce,
  defender: TaskForce,
  systemId: SystemId = 0,
  seed: int64 = 12345
): CombatResult =
  ## Convenience function for simple 1v1 battles
  let context = BattleContext(
    systemId: systemId,
    taskForces: @[attacker, defender],
    seed: seed,
    maxRounds: 20
  )

  return resolveCombat(context)
