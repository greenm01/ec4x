## Ground Combat and Planetary Bombardment
##
## Implements planetary bombardment, invasion, and blitz mechanics.
## Separate from space combat but shares some systems (CER, damage application).
##
## Based on EC4X specifications:
## - Section 7.5: Planetary Bombardment
## - Section 7.6: Planetary Invasion & Blitz
## - Section 2.4.8: Planet-Breaker shield penetration

import std/[options, math, tables, sequtils]
import ../../types/[combat as combat_types, core, ground_unit, game_state, squadron, ship]
import ../../state/entity_manager
import ../../globals
import cer

export combat_types

## Bombardment CER Table (Section 7.5.1)
proc getBombardmentCER*(roll: int): (float, bool) =
  ## Get bombardment CER multiplier and critical hit flag from config
  ## Returns (multiplier, isCritical)
  ##
  ## Reads from config/combat.kdl bombardment thresholds
  let cfg = gameConfig.combat.bombardment

  if roll <= cfg.veryPoorMax:
    # Roll 0-2: 0.25× (round up)
    return (0.25, false)
  elif roll <= cfg.poorMax:
    # Roll 3-5: 0.50× (round up)
    return (0.50, false)
  elif roll <= 8:
    # Roll 6-8: 1.00×
    return (1.0, false)
  elif roll == 9:
    # Roll 9: 1.00× (critical - affects attackers only)
    return (1.0, true)
  else:
    # Fallback (should never happen)
    return (0.25, false)

## Ground Combat CER Table (Section 7.6)

proc getGroundCombatCER*(roll: int): float =
  ## Get ground combat CER multiplier (invasion/blitz) from config
  ##
  ## Reads from config/combat.kdl ground combat thresholds
  let cfg = gameConfig.combat.groundCombat

  if roll <= cfg.poorMax:
    # Roll 0-2: 0.50× (round up)
    return 0.5
  elif roll <= cfg.averageMax:
    # Roll 3-6: 1.00×
    return 1.0
  elif roll <= cfg.goodMax:
    # Roll 7-8: 1.50× (round up)
    return 1.5
  elif roll >= cfg.critical:
    # Roll 9: 2.00×
    return 2.0
  else:
    # Fallback
    return 0.5

## Planetary Shield Mechanics (Section 7.5.2)

proc getShieldData*(shieldLevel: int): (int, float) =
  ## Get shield data from config for given level (1-6)
  ## Returns (rollNeeded, blockPct)
  ##
  ## Reads from config/tech.kdl shields section
  if shieldLevel < 1 or shieldLevel > 6:
    return (20, 0.0) # Invalid level - shield never activates

  # Look up shield level data from tech config
  let key = int32(shieldLevel)
  if not gameConfig.tech.sld.levels.hasKey(key):
    return (20, 0.0) # Level not in config

  let sldData = gameConfig.tech.sld.levels[key]
  return (int(sldData.d20Threshold), float(sldData.hitsBlocked))

proc rollShieldBlock*(shieldLevel: int, rng: var CombatRNG): (bool, float) =
  ## Roll to see if shields block damage
  ## Returns (blocked, percentage_to_block)
  ##
  ## Uses 1d20 roll (not 1d10) per spec

  if shieldLevel < 1 or shieldLevel > 6:
    return (false, 0.0)

  let (rollNeeded, blockPct) = getShieldData(shieldLevel)

  # Roll 1d20 using proper function from CER module
  let roll = rng.roll1d20()

  if roll >= rollNeeded:
    return (true, blockPct)
  else:
    return (false, 0.0)

proc applyShieldReduction*(hits: int, shieldLevel: int, rng: var CombatRNG): int =
  ## Apply shield reduction to bombardment hits
  ## Returns effective hits after shield blocking

  let (blocked, pct) = rollShieldBlock(shieldLevel, rng)
  if not blocked:
    return hits

  # Reduce hits by percentage, round up
  let reduction = ceil(float(hits) * pct).int
  return max(0, hits - reduction)

## Planet-Breaker Shield Penetration (Section 7.5.2)

proc separatePlanetBreakerAS*(
    state: GameState, squadrons: seq[CombatSquadron]
): (int, int) =
  ## Separate Planet-Breaker AS from conventional ship AS
  ## Returns (planet_breaker_as, conventional_as)
  ##
  ## Planet-Breakers bypass shields completely
  ## Uses proper DoD pattern: lookup squadron via entity manager

  var pbAS = 0
  var convAS = 0

  for sq in squadrons:
    if sq.state == CombatState.Destroyed:
      continue

    let currentAS =
      if sq.state == CombatState.Crippled:
        max(1'i32, sq.attackStrength div 2)
      else:
        sq.attackStrength

    # Look up squadron to check if it has Planet-Breaker flagship
    let squadronOpt = state.squadrons.entities.entity(sq.squadronId)
    if squadronOpt.isSome:
      let squadron = squadronOpt.get()
      let flagshipOpt = state.ships.entities.entity(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        if flagship.shipClass == ShipClass.PlanetBreaker:
          pbAS += int(currentAS)
        else:
          convAS += int(currentAS)
      else:
        convAS += int(currentAS) # No flagship found, treat as conventional
    else:
      convAS += int(currentAS) # No squadron found, treat as conventional

  return (pbAS, convAS)

## Bombardment Resolution (Section 7.5)

proc resolveBombardmentRound*(
    state: var GameState,
    attackingFleet: var seq[CombatSquadron],
    defense: var PlanetaryDefense,
    rng: var CombatRNG,
): BombardmentResult =
  ## Resolve one round of planetary bombardment (max 3 per turn)
  ## Implements Section 7.5.1-7.5.4
  ##
  ## Ground batteries fire back at bombarding ships (Section 7.5.3)
  ## Uses proper DoD entity patterns - reads via entity(), writes via updateEntity()

  result = BombardmentResult()

  # Calculate attacking AS (separate Planet-Breakers from conventional)
  let (pbAS, convAS) = separatePlanetBreakerAS(state, attackingFleet)
  let totalAttackerAS = pbAS + convAS

  # Calculate defending AS (ground batteries only attack back)
  # Use proper entity pattern: read via entity()
  var defenderAS = 0
  for batteryId in defense.groundBatteryIds:
    let batteryOpt = state.groundUnits.entities.entity(batteryId)
    if batteryOpt.isNone:
      continue
    let battery = batteryOpt.get()

    if battery.state == CombatState.Destroyed:
      continue
    let batteryAS =
      if battery.state == CombatState.Crippled:
        max(1, battery.stats.attackStrength div 2)
      else:
        battery.stats.attackStrength
    defenderAS += batteryAS

  # Both sides roll CER
  let attackRoll = rng.roll1d10()
  let defenseRoll = rng.roll1d10()

  let (attackCER, attackCrit) = getBombardmentCER(attackRoll)
  let (defenseCER, defenseCrit) = getBombardmentCER(defenseRoll)

  # Calculate base hits
  var attackerHits = ceil(float(totalAttackerAS) * attackCER).int
  let defenderHits = ceil(float(defenderAS) * defenseCER).int

  # Apply shield reduction to conventional hits only (Section 7.5.2)
  var effectiveConvHits = ceil(float(convAS) * attackCER).int
  let pbHits = ceil(float(pbAS) * attackCER).int

  if defense.shields.isSome:
    effectiveConvHits =
      applyShieldReduction(effectiveConvHits, defense.shields.get.level, rng)
    result.shieldBlocked = int32(ceil(float(convAS) * attackCER).int - effectiveConvHits)

  # Planet-Breaker hits bypass shields entirely
  attackerHits = pbHits + effectiveConvHits
  result.attackerHits = int32(attackerHits)
  result.defenderHits = int32(defenderHits)

  # Apply damage to ground batteries (Section 7.5.3)
  # Use proper entity pattern: read, mutate copy, write back via updateEntity()
  var excessAttackerHits = attackerHits
  for batteryId in defense.groundBatteryIds:
    if excessAttackerHits <= 0:
      break

    let batteryOpt = state.groundUnits.entities.entity(batteryId)
    if batteryOpt.isNone:
      continue
    var battery = batteryOpt.get()

    if battery.state == CombatState.Destroyed:
      continue

    if excessAttackerHits >= battery.stats.defenseStrength:
      # Enough hits to reduce this battery
      excessAttackerHits -= battery.stats.defenseStrength

      case battery.state
      of CombatState.Undamaged:
        battery.state = CombatState.Crippled
        battery.stats = GroundUnitStats(
          unitType: battery.stats.unitType,
          attackStrength: max(1, battery.stats.attackStrength div 2),
          defenseStrength: battery.stats.defenseStrength,
        )
        result.batteriesCrippled += 1
      of CombatState.Crippled:
        # Check destruction protection
        # Check if all other batteries are crippled/destroyed
        var allOthersCrippled = true
        for otherId in defense.groundBatteryIds:
          if otherId == batteryId:
            continue
          let otherOpt = state.groundUnits.entities.entity(otherId)
          if otherOpt.isSome and otherOpt.get().state == CombatState.Undamaged:
            allOthersCrippled = false
            break

        if allOthersCrippled or attackCrit:
          battery.state = CombatState.Destroyed
          result.batteriesDestroyed += 1
      of CombatState.Destroyed:
        discard

      # Write back changes via updateEntity()
      state.groundUnits.entities.updateEntity(batteryId, battery)

  # Apply excess hits to ground forces (Section 7.5.4)
  # Use proper entity pattern: read, mutate copy, write back via updateEntity()
  if excessAttackerHits > 0:
    for unitId in defense.groundForceIds:
      if excessAttackerHits <= 0:
        break

      let unitOpt = state.groundUnits.entities.entity(unitId)
      if unitOpt.isNone:
        continue
      var unit = unitOpt.get()

      if unit.state == CombatState.Destroyed:
        continue

      if excessAttackerHits >= unit.stats.defenseStrength:
        excessAttackerHits -= unit.stats.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.stats = GroundUnitStats(
            unitType: unit.stats.unitType,
            attackStrength: max(1, unit.stats.attackStrength div 2),
            defenseStrength: unit.stats.defenseStrength,
          )
        of CombatState.Crippled:
          # Check if all other ground forces are crippled/destroyed
          var allOthersCrippled = true
          for otherId in defense.groundForceIds:
            if otherId == unitId:
              continue
            let otherOpt = state.groundUnits.entities.entity(otherId)
            if otherOpt.isSome and otherOpt.get().state == CombatState.Undamaged:
              allOthersCrippled = false
              break

          if allOthersCrippled:
            unit.state = CombatState.Destroyed
        of CombatState.Destroyed:
          discard

        # Write back changes via updateEntity()
        state.groundUnits.entities.updateEntity(unitId, unit)

  # Remaining excess hits damage infrastructure (IU then PU)
  # Per user requirement: IU and PU both take damage during bombardment
  # IU represents factories/infrastructure, PU represents civilian casualties
  # Damage is split: each excess hit damages both IU and PU
  result.infrastructureDamage = int32(excessAttackerHits)
  result.populationDamage = int32(excessAttackerHits)
    # Same damage to both (bombardment is indiscriminate)

  # Apply defender hits to attacking fleet (critical hits bypass protection)
  var excessDefenderHits = defenderHits
  for squadron in attackingFleet.mitems:
    if squadron.state == CombatState.Destroyed or excessDefenderHits <= 0:
      continue

    # Use cached defense strength from CombatSquadron
    if excessDefenderHits >= int(squadron.defenseStrength):
      excessDefenderHits -= int(squadron.defenseStrength)

      case squadron.state
      of CombatState.Undamaged:
        squadron.state = CombatState.Crippled
        result.squadronsCrippled += 1
      of CombatState.Crippled:
        # Check destruction protection (unless critical hit)
        let allOthersCrippled = attackingFleet.allIt(
          it.squadronId == squadron.squadronId or it.state != CombatState.Undamaged
        )
        if allOthersCrippled or defenseCrit:
          squadron.state = CombatState.Destroyed
          result.squadronsDestroyed += 1
      of CombatState.Destroyed:
        discard

  result.roundsCompleted = 1

proc conductBombardment*(
    state: var GameState,
    attackingFleet: var seq[CombatSquadron],
    defense: var PlanetaryDefense,
    seed: int64,
    maxRounds: int = 3,
): BombardmentResult =
  ## Conduct full bombardment (up to 3 rounds per turn)
  ## Section 7.5: "No more than three combat rounds are conducted per turn"
  ##
  ## Attacking squadrons can be crippled/destroyed by ground battery counter-fire
  ## Uses proper DoD entity patterns

  var rng = initRNG(seed)
  result = BombardmentResult()

  for round in 1 .. maxRounds:
    let roundResult = resolveBombardmentRound(state, attackingFleet, defense, rng)

    # Accumulate results
    result.attackerHits += roundResult.attackerHits
    result.defenderHits += roundResult.defenderHits
    result.shieldBlocked += roundResult.shieldBlocked
    result.batteriesDestroyed += roundResult.batteriesDestroyed
    result.batteriesCrippled += roundResult.batteriesCrippled
    result.squadronsDestroyed += roundResult.squadronsDestroyed
    result.squadronsCrippled += roundResult.squadronsCrippled
    result.infrastructureDamage += roundResult.infrastructureDamage
    result.roundsCompleted += 1

    # Stop if all batteries destroyed
    # Use proper entity pattern to check battery states
    var batteriesRemaining = false
    for batteryId in defense.groundBatteryIds:
      let batteryOpt = state.groundUnits.entities.entity(batteryId)
      if batteryOpt.isSome and batteryOpt.get().state != CombatState.Destroyed:
        batteriesRemaining = true
        break

    if not batteriesRemaining:
      break

## Planetary Invasion (Section 7.6.1)

proc conductInvasion*(
    state: var GameState,
    attackingForces: seq[GroundUnit],
    defendingForces: seq[GroundUnit],
    defense: var PlanetaryDefense,
    seed: int64,
): InvasionResult =
  ## Conduct planetary invasion (Section 7.6.1)
  ##
  ## Prerequisites:
  ## 1. All ground batteries must be destroyed (via bombardment first)
  ## 2. Marines must be present in attacking forces
  ##
  ## Effects on success:
  ## - Shields and spaceports destroyed immediately on landing
  ## - 50% of remaining IU destroyed by loyal citizens
  ## Uses proper DoD entity patterns

  var rng = initRNG(seed)
  result = InvasionResult()

  # Check prerequisites - all batteries must be destroyed
  # Use proper entity pattern to check battery states
  var batteriesDestroyed = true
  for batteryId in defense.groundBatteryIds:
    let batteryOpt = state.groundUnits.entities.entity(batteryId)
    if batteryOpt.isSome and batteryOpt.get().state != CombatState.Destroyed:
      batteriesDestroyed = false
      break

  if not batteriesDestroyed:
    result.success = false
    return

  # Marines land - shields and spaceports destroyed immediately
  defense.shields = none(ShieldLevel)
  defense.spaceport = false

  # Make mutable copies of forces for combat
  var attackers = attackingForces
  var defenders = defendingForces

  # Ground combat loop - repeat until one side eliminated
  while true:
    # Calculate AS for both sides
    var attackerAS = 0
    for unit in attackers:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS =
        if unit.state == CombatState.Crippled:
          max(1, unit.stats.attackStrength div 2)
        else:
          unit.stats.attackStrength
      attackerAS += unitAS

    var defenderAS = 0
    for unit in defenders:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS =
        if unit.state == CombatState.Crippled:
          max(1, unit.stats.attackStrength div 2)
        else:
          unit.stats.attackStrength
      defenderAS += unitAS

    # Roll on Ground Combat Table
    let attackRoll = rng.roll1d10()
    let defenseRoll = rng.roll1d10()

    let attackCER = getGroundCombatCER(attackRoll)
    let defenseCER = getGroundCombatCER(defenseRoll)

    let attackerHits = ceil(float(attackerAS) * attackCER).int
    let defenderHits = ceil(float(defenderAS) * defenseCER).int

    # Apply hits to defenders (Section 7.6.1 restrictions)
    var excessAttackerHits = attackerHits
    for unit in defenders.mitems:
      if unit.state == CombatState.Destroyed or excessAttackerHits <= 0:
        continue

      if excessAttackerHits >= unit.stats.defenseStrength:
        excessAttackerHits -= unit.stats.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.stats = GroundUnitStats(
            unitType: unit.stats.unitType,
            attackStrength: max(1, unit.stats.attackStrength div 2),
            defenseStrength: unit.stats.defenseStrength,
          )
          result.defenderCasualties.add(unit.id)
        of CombatState.Crippled:
          let allOthersCrippled =
            defenders.allIt(it.id == unit.id or it.state != CombatState.Undamaged)
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.defenderCasualties.add(unit.id)
        of CombatState.Destroyed:
          discard

    # Apply hits to attackers
    var excessDefenderHits = defenderHits
    for unit in attackers.mitems:
      if unit.state == CombatState.Destroyed or excessDefenderHits <= 0:
        continue

      if excessDefenderHits >= unit.stats.defenseStrength:
        excessDefenderHits -= unit.stats.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.stats = GroundUnitStats(
            unitType: unit.stats.unitType,
            attackStrength: max(1, unit.stats.attackStrength div 2),
            defenseStrength: unit.stats.defenseStrength,
          )
          result.attackerCasualties.add(unit.id)
        of CombatState.Crippled:
          let allOthersCrippled =
            attackers.allIt(it.id == unit.id or it.state != CombatState.Undamaged)
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.attackerCasualties.add(unit.id)
        of CombatState.Destroyed:
          discard

    # Check termination
    let attackersAlive = attackers.anyIt(it.state != CombatState.Destroyed)
    let defendersAlive = defenders.anyIt(it.state != CombatState.Destroyed)

    if not attackersAlive or not defendersAlive:
      result.success = attackersAlive and not defendersAlive
      if result.success:
        # 50% IU destroyed by loyal citizens
        result.infrastructureDestroyed = 50 # Percentage
      break

## Planetary Blitz (Section 7.6.2)

proc conductBlitz*(
    state: var GameState,
    attackingFleet: var seq[CombatSquadron],
    attackingForces: seq[GroundUnit],
    defendingForces: seq[GroundUnit],
    defense: var PlanetaryDefense,
    seed: int64,
): InvasionResult =
  ## Conduct planetary blitz (fast insertion) - Section 7.6.2
  ##
  ## Differences from invasion:
  ## 1. One round vs ground batteries (transports can be destroyed)
  ## 2. Marines get 0.5× AS modifier (quick insertion penalty)
  ## 3. No IU destroyed on success (assets seized intact)
  ## 4. Shields, spaceports, batteries seized if successful
  ## Uses proper DoD entity patterns

  var rng = initRNG(seed)
  result = InvasionResult()
  result.batteriesDestroyed = 0 # Initialize battery count

  # Phase 1: One round of bombardment (transports vulnerable)
  # Section 7.6.2: "Troop transports are included as individual units"
  # Fleet is now mutable - transports can be damaged by battery fire
  let bombardmentResult =
    resolveBombardmentRound(state, attackingFleet, defense, rng)

  # Track battery destruction for intelligence reporting
  result.batteriesDestroyed = bombardmentResult.batteriesDestroyed

  # Check if transports survived (simplified - track in fleet)
  # In full implementation, transports would be in attackingFleet

  # Phase 2: Ground combat with Marines at 0.5× AS
  var attackers = attackingForces
  var defenders = defendingForces

  # Apply Marine AS penalty for quick insertion
  for unit in attackers.mitems:
    if unit.stats.unitType == GroundClass.Marine:
      unit.stats = GroundUnitStats(
        unitType: unit.stats.unitType,
        attackStrength: max(1, unit.stats.attackStrength div 2),
        defenseStrength: unit.stats.defenseStrength,
      )

  # Ground combat loop
  while true:
    var attackerAS = 0
    for unit in attackers:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS =
        if unit.state == CombatState.Crippled:
          max(1, unit.stats.attackStrength div 2)
        else:
          unit.stats.attackStrength
      attackerAS += unitAS

    var defenderAS = 0
    for unit in defenders:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS =
        if unit.state == CombatState.Crippled:
          max(1, unit.stats.attackStrength div 2)
        else:
          unit.stats.attackStrength
      defenderAS += unitAS

    # Roll on Ground Combat Table
    let attackRoll = rng.roll1d10()
    let defenseRoll = rng.roll1d10()

    let attackCER = getGroundCombatCER(attackRoll)
    let defenseCER = getGroundCombatCER(defenseRoll)

    let attackerHits = ceil(float(attackerAS) * attackCER).int
    let defenderHits = ceil(float(defenderAS) * defenseCER).int

    # Apply hits to defenders
    var excessAttackerHits = attackerHits
    for unit in defenders.mitems:
      if unit.state == CombatState.Destroyed or excessAttackerHits <= 0:
        continue

      if excessAttackerHits >= unit.stats.defenseStrength:
        excessAttackerHits -= unit.stats.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.stats = GroundUnitStats(
            unitType: unit.stats.unitType,
            attackStrength: max(1, unit.stats.attackStrength div 2),
            defenseStrength: unit.stats.defenseStrength,
          )
          result.defenderCasualties.add(unit.id)
        of CombatState.Crippled:
          let allOthersCrippled =
            defenders.allIt(it.id == unit.id or it.state != CombatState.Undamaged)
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.defenderCasualties.add(unit.id)
        of CombatState.Destroyed:
          discard

    # Apply hits to attackers
    var excessDefenderHits = defenderHits
    for unit in attackers.mitems:
      if unit.state == CombatState.Destroyed or excessDefenderHits <= 0:
        continue

      if excessDefenderHits >= unit.stats.defenseStrength:
        excessDefenderHits -= unit.stats.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.stats = GroundUnitStats(
            unitType: unit.stats.unitType,
            attackStrength: max(1, unit.stats.attackStrength div 2),
            defenseStrength: unit.stats.defenseStrength,
          )
          result.attackerCasualties.add(unit.id)
        of CombatState.Crippled:
          let allOthersCrippled =
            attackers.allIt(it.id == unit.id or it.state != CombatState.Undamaged)
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.attackerCasualties.add(unit.id)
        of CombatState.Destroyed:
          discard

    # Check termination
    let attackersAlive = attackers.anyIt(it.state != CombatState.Destroyed)
    let defendersAlive = defenders.anyIt(it.state != CombatState.Destroyed)

    if not attackersAlive or not defendersAlive:
      result.success = attackersAlive and not defendersAlive
      if result.success:
        # Assets seized intact (no IU destruction)
        result.assetsSeized = true
        result.infrastructureDestroyed = 0
      break

## Notes for Future Implementation
##
## 1. Ground Combat State Persistence:
##    - Ground units and batteries persist between turns
##    - Crippled units have reduced AS (× 0.5)
##    - Must be saved in colony/system state
##
## 2. Order of Operations:
##    - Bombardment: Space fleet vs ground batteries (3 rounds max)
##    - Invasion: One bombardment round, then ground combat
##    - Blitz: One round vs batteries (transports vulnerable), then ground combat
##
## 3. Damage Application Rules:
##    - Same destruction protection as space combat
##    - Units not destroyed until all others crippled
##    - Critical hits bypass protection (bombardment only, attacker only)
##    - Excess hits flow: Batteries → Ground Forces → IU → PU
##
## 4. Special Cases:
##    - Planet-Breakers bypass shields entirely
##    - Mixed fleets split damage calculation (PB vs conventional)
##    - Shields only destroyed by Marines during invasion
##    - Blitz seized assets: shields, spaceports, batteries, IU (all intact)
##
## 5. Integration with Turn Resolution:
##    - Bombardment/Invasion orders processed after space combat
##    - Only victorious fleets can bombard/invade
##    - Defeated/retreated fleets cannot proceed to ground phase
