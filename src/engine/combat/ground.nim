## Ground Combat and Planetary Bombardment
##
## Implements planetary bombardment, invasion, and blitz mechanics.
## Separate from space combat but shares some systems (CER, damage application).
##
## Based on EC4X specifications:
## - Section 7.5: Planetary Bombardment
## - Section 7.6: Planetary Invasion & Blitz
## - Section 2.4.8: Planet-Breaker shield penetration

import std/[options, sequtils, math]
import types, cer
import ../../common/types/[core, units, combat as commonCombat]
import ../squadron
import ../config/combat_config
import ../config/ground_units_config

export CombatState

## Ground Combat Types

type
  GroundUnitType* {.pure.} = enum
    ## Types of ground forces
    Army,           # Garrison forces (defense)
    Marine,         # Invasion forces (offense)
    GroundBattery,  # Planetary defense weapons
    Spacelift       # Transport ships (Blitz only)

  GroundUnit* = object
    ## Individual ground combat unit
    unitType*: GroundUnitType
    id*: string
    owner*: HouseId
    attackStrength*: int
    defenseStrength*: int
    state*: CombatState  # Undamaged, Crippled, Destroyed

  PlanetaryDefense* = object
    ## Complete planetary defense setup
    shields*: Option[ShieldLevel]  # SLD1-SLD6
    groundBatteries*: seq[GroundUnit]
    groundForces*: seq[GroundUnit]  # Armies and Marines
    spaceport*: bool  # Destroyed during invasion

  ShieldLevel* = object
    ## Planetary shield information (per reference.md Section 9.3)
    level*: int  # 1-6 (SLD1-SLD6)
    blockChance*: float  # Probability shield blocks damage
    blockPercentage*: float  # % of hits blocked if successful

  BombardmentResult* = object
    ## Result of one bombardment round
    attackerHits*: int
    defenderHits*: int
    shieldBlocked*: int  # Hits blocked by shields
    batteriesDestroyed*: int
    batteriesCrippled*: int
    squadronsDestroyed*: int
    squadronsCrippled*: int
    infrastructureDamage*: int  # IU lost
    populationDamage*: int  # PU lost
    roundsCompleted*: int  # 1-3 max per turn

  InvasionResult* = object
    ## Result of planetary invasion or blitz
    success*: bool
    attacker*: HouseId
    defender*: HouseId
    attackerCasualties*: seq[GroundUnit]
    defenderCasualties*: seq[GroundUnit]
    infrastructureDestroyed*: int  # IU lost (50% on invasion success)
    assetsSeized*: bool  # True for blitz, false for invasion

## Bombardment CER Table (Section 7.5.1)

proc getBombardmentCER*(roll: int): (float, bool) =
  ## Get bombardment CER multiplier and critical hit flag from config
  ## Returns (multiplier, isCritical)
  ##
  ## Uses config/combat.toml bombardment thresholds
  let cfg = globalCombatConfig.bombardment

  if roll <= cfg.very_poor_max:
    # Roll 0-2: 0.25× (round up)
    return (0.25, false)
  elif roll <= cfg.poor_max:
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
  ## Uses config/combat.toml ground_combat thresholds
  let cfg = globalCombatConfig.ground_combat

  if roll <= cfg.poor_max:
    # Roll 0-2: 0.50× (round up)
    return 0.5
  elif roll <= cfg.average_max:
    # Roll 3-6: 1.00×
    return 1.0
  elif roll <= cfg.good_max:
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
  ## Uses config/combat.toml planetary_shields section
  let cfg = globalCombatConfig.planetary_shields

  case shieldLevel
  of 1:
    return (cfg.sld1_roll, float(cfg.sld1_block) / 100.0)
  of 2:
    return (cfg.sld2_roll, float(cfg.sld2_block) / 100.0)
  of 3:
    return (cfg.sld3_roll, float(cfg.sld3_block) / 100.0)
  of 4:
    return (cfg.sld4_roll, float(cfg.sld4_block) / 100.0)
  of 5:
    return (cfg.sld5_roll, float(cfg.sld5_block) / 100.0)
  of 6:
    return (cfg.sld6_roll, float(cfg.sld6_block) / 100.0)
  else:
    return (20, 0.0)  # Invalid level - shield never activates

proc rollShieldBlock*(shieldLevel: int, rng: var CombatRNG): (bool, float) =
  ## Roll to see if shields block damage
  ## Returns (blocked, percentage_to_block)
  ##
  ## Uses 1d20 roll (not 1d10) per spec

  if shieldLevel < 1 or shieldLevel > 6:
    return (false, 0.0)

  let (rollNeeded, blockPct) = getShieldData(shieldLevel)

  # Roll 1d20 (extend RNG to support d20)
  # TODO: Add roll1d20() to CER module
  let roll = (rng.roll1d10() * 2) mod 20 + 1  # TEMP: Simulate d20

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

proc separatePlanetBreakerAS*(squadrons: seq[CombatSquadron]): (int, int) =
  ## Separate Planet-Breaker AS from conventional ship AS
  ## Returns (planet_breaker_as, conventional_as)
  ##
  ## Planet-Breakers bypass shields completely

  var pbAS = 0
  var convAS = 0

  for sq in squadrons:
    if sq.state == CombatState.Destroyed:
      continue

    let currentAS = sq.getCurrentAS()

    # Note: Squadron is nested inside CombatSquadron
    if sq.squadron.flagship.shipClass == ShipClass.PlanetBreaker:
      pbAS += currentAS
    else:
      convAS += currentAS

  return (pbAS, convAS)

## Bombardment Resolution (Section 7.5)

proc resolveBombardmentRound*(
  attackingFleet: seq[CombatSquadron],
  defense: var PlanetaryDefense,
  rng: var CombatRNG
): BombardmentResult =
  ## Resolve one round of planetary bombardment (max 3 per turn)
  ## Implements Section 7.5.1-7.5.4

  result = BombardmentResult()

  # Calculate attacking AS (separate Planet-Breakers from conventional)
  let (pbAS, convAS) = separatePlanetBreakerAS(attackingFleet)
  let totalAttackerAS = pbAS + convAS

  # Calculate defending AS (ground batteries only attack back)
  var defenderAS = 0
  for battery in defense.groundBatteries:
    if battery.state == CombatState.Destroyed:
      continue
    let batteryAS = if battery.state == CombatState.Crippled:
      max(1, battery.attackStrength div 2)
    else:
      battery.attackStrength
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
    effectiveConvHits = applyShieldReduction(effectiveConvHits, defense.shields.get.level, rng)
    result.shieldBlocked = (ceil(float(convAS) * attackCER).int - effectiveConvHits)

  # Planet-Breaker hits bypass shields entirely
  attackerHits = pbHits + effectiveConvHits
  result.attackerHits = attackerHits
  result.defenderHits = defenderHits

  # Apply damage to ground batteries (Section 7.5.3)
  var excessAttackerHits = attackerHits
  for battery in defense.groundBatteries.mitems:
    if battery.state == CombatState.Destroyed or excessAttackerHits <= 0:
      continue

    if excessAttackerHits >= battery.defenseStrength:
      # Enough hits to reduce this battery
      excessAttackerHits -= battery.defenseStrength

      case battery.state
      of CombatState.Undamaged:
        battery.state = CombatState.Crippled
        battery.attackStrength = max(1, battery.attackStrength div 2)
        result.batteriesCrippled += 1
      of CombatState.Crippled:
        # Check destruction protection
        let allOthersCrippled = defense.groundBatteries.allIt(
          it.id == battery.id or it.state != CombatState.Undamaged
        )
        if allOthersCrippled or attackCrit:
          battery.state = CombatState.Destroyed
          result.batteriesDestroyed += 1
      of CombatState.Destroyed:
        discard

  # Apply excess hits to ground forces (Section 7.5.4)
  if excessAttackerHits > 0:
    for unit in defense.groundForces.mitems:
      if unit.state == CombatState.Destroyed or excessAttackerHits <= 0:
        continue

      if excessAttackerHits >= unit.defenseStrength:
        excessAttackerHits -= unit.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.attackStrength = max(1, unit.attackStrength div 2)
        of CombatState.Crippled:
          let allOthersCrippled = defense.groundForces.allIt(
            it.id == unit.id or it.state != CombatState.Undamaged
          )
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
        of CombatState.Destroyed:
          discard

  # Remaining excess hits damage infrastructure (IU then PU)
  result.infrastructureDamage = excessAttackerHits

  # Apply defender hits to attacking fleet (critical hits bypass protection)
  var excessDefenderHits = defenderHits
  for squadron in attackingFleet:
    if squadron.state == CombatState.Destroyed or excessDefenderHits <= 0:
      continue

    let squadronDS = squadron.squadron.flagship.stats.defenseStrength
    if excessDefenderHits >= squadronDS:
      excessDefenderHits -= squadronDS
      # Note: Would need mutable access to apply damage
      # This is tracked separately in the combat result
      case squadron.state
      of CombatState.Undamaged:
        result.squadronsCrippled += 1
      of CombatState.Crippled:
        if defenseCrit:
          result.squadronsDestroyed += 1
      of CombatState.Destroyed:
        discard

  result.roundsCompleted = 1

proc conductBombardment*(
  attackingFleet: seq[CombatSquadron],
  defense: var PlanetaryDefense,
  seed: int64,
  maxRounds: int = 3
): BombardmentResult =
  ## Conduct full bombardment (up to 3 rounds per turn)
  ## Section 7.5: "No more than three combat rounds are conducted per turn"

  var rng = initRNG(seed)
  result = BombardmentResult()

  for round in 1..maxRounds:
    let roundResult = resolveBombardmentRound(attackingFleet, defense, rng)

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
    let batteriesRemaining = defense.groundBatteries.anyIt(it.state != CombatState.Destroyed)
    if not batteriesRemaining:
      break

## Planetary Invasion (Section 7.6.1)

proc conductInvasion*(
  attackingForces: seq[GroundUnit],
  defendingForces: seq[GroundUnit],
  defense: var PlanetaryDefense,
  seed: int64
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

  var rng = initRNG(seed)
  result = InvasionResult()

  # Check prerequisites
  let batteriesDestroyed = defense.groundBatteries.allIt(it.state == CombatState.Destroyed)
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
      let unitAS = if unit.state == CombatState.Crippled:
        max(1, unit.attackStrength div 2)
      else:
        unit.attackStrength
      attackerAS += unitAS

    var defenderAS = 0
    for unit in defenders:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS = if unit.state == CombatState.Crippled:
        max(1, unit.attackStrength div 2)
      else:
        unit.attackStrength
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

      if excessAttackerHits >= unit.defenseStrength:
        excessAttackerHits -= unit.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.attackStrength = max(1, unit.attackStrength div 2)
          result.defenderCasualties.add(unit)
        of CombatState.Crippled:
          let allOthersCrippled = defenders.allIt(
            it.id == unit.id or it.state != CombatState.Undamaged
          )
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.defenderCasualties.add(unit)
        of CombatState.Destroyed:
          discard

    # Apply hits to attackers
    var excessDefenderHits = defenderHits
    for unit in attackers.mitems:
      if unit.state == CombatState.Destroyed or excessDefenderHits <= 0:
        continue

      if excessDefenderHits >= unit.defenseStrength:
        excessDefenderHits -= unit.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.attackStrength = max(1, unit.attackStrength div 2)
          result.attackerCasualties.add(unit)
        of CombatState.Crippled:
          let allOthersCrippled = attackers.allIt(
            it.id == unit.id or it.state != CombatState.Undamaged
          )
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.attackerCasualties.add(unit)
        of CombatState.Destroyed:
          discard

    # Check termination
    let attackersAlive = attackers.anyIt(it.state != CombatState.Destroyed)
    let defendersAlive = defenders.anyIt(it.state != CombatState.Destroyed)

    if not attackersAlive or not defendersAlive:
      result.success = attackersAlive and not defendersAlive
      if result.success:
        # 50% IU destroyed by loyal citizens
        result.infrastructureDestroyed = 50  # Percentage
      break

## Planetary Blitz (Section 7.6.2)

proc conductBlitz*(
  attackingFleet: seq[CombatSquadron],
  attackingForces: seq[GroundUnit],
  defense: var PlanetaryDefense,
  seed: int64
): InvasionResult =
  ## Conduct planetary blitz (fast insertion) - Section 7.6.2
  ##
  ## Differences from invasion:
  ## 1. One round vs ground batteries (transports can be destroyed)
  ## 2. Marines get 0.5× AS modifier (quick insertion penalty)
  ## 3. No IU destroyed on success (assets seized intact)
  ## 4. Shields, spaceports, batteries seized if successful

  var rng = initRNG(seed)
  result = InvasionResult()

  # Phase 1: One round of bombardment (transports vulnerable)
  # Section 7.6.2: "Troop transports are included as individual units"
  # Note: This would need mutable fleet access, simplified for now
  discard resolveBombardmentRound(attackingFleet, defense, rng)

  # Check if transports survived (simplified - track in fleet)
  # In full implementation, transports would be in attackingFleet

  # Phase 2: Ground combat with Marines at 0.5× AS
  var attackers = attackingForces
  var defenders = defense.groundForces

  # Apply Marine AS penalty for quick insertion
  for unit in attackers.mitems:
    if unit.unitType == GroundUnitType.Marine:
      unit.attackStrength = max(1, unit.attackStrength div 2)

  # Ground combat loop
  while true:
    var attackerAS = 0
    for unit in attackers:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS = if unit.state == CombatState.Crippled:
        max(1, unit.attackStrength div 2)
      else:
        unit.attackStrength
      attackerAS += unitAS

    var defenderAS = 0
    for unit in defenders:
      if unit.state == CombatState.Destroyed:
        continue
      let unitAS = if unit.state == CombatState.Crippled:
        max(1, unit.attackStrength div 2)
      else:
        unit.attackStrength
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

      if excessAttackerHits >= unit.defenseStrength:
        excessAttackerHits -= unit.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.attackStrength = max(1, unit.attackStrength div 2)
          result.defenderCasualties.add(unit)
        of CombatState.Crippled:
          let allOthersCrippled = defenders.allIt(
            it.id == unit.id or it.state != CombatState.Undamaged
          )
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.defenderCasualties.add(unit)
        of CombatState.Destroyed:
          discard

    # Apply hits to attackers
    var excessDefenderHits = defenderHits
    for unit in attackers.mitems:
      if unit.state == CombatState.Destroyed or excessDefenderHits <= 0:
        continue

      if excessDefenderHits >= unit.defenseStrength:
        excessDefenderHits -= unit.defenseStrength
        case unit.state
        of CombatState.Undamaged:
          unit.state = CombatState.Crippled
          unit.attackStrength = max(1, unit.attackStrength div 2)
          result.attackerCasualties.add(unit)
        of CombatState.Crippled:
          let allOthersCrippled = attackers.allIt(
            it.id == unit.id or it.state != CombatState.Undamaged
          )
          if allOthersCrippled:
            unit.state = CombatState.Destroyed
            result.attackerCasualties.add(unit)
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

## Ground Unit Management

proc createGroundBattery*(
  id: string,
  owner: HouseId,
  techLevel: int = 1
): GroundUnit =
  ## Create a ground battery unit from config
  ## Stats loaded from config/ground_units.toml
  ##
  ## TODO M3: Apply tech modifiers if applicable

  let cfg = globalGroundUnitsConfig.ground_battery

  result = GroundUnit(
    unitType: GroundUnitType.GroundBattery,
    id: id,
    owner: owner,
    attackStrength: cfg.attack_strength,
    defenseStrength: cfg.defense_strength,
    state: CombatState.Undamaged
  )

proc createArmy*(
  id: string,
  owner: HouseId
): GroundUnit =
  ## Create an Army unit (garrison defense) from config
  ## Stats loaded from config/ground_units.toml

  let cfg = globalGroundUnitsConfig.army

  result = GroundUnit(
    unitType: GroundUnitType.Army,
    id: id,
    owner: owner,
    attackStrength: cfg.attack_strength,
    defenseStrength: cfg.defense_strength,
    state: CombatState.Undamaged
  )

proc createMarine*(
  id: string,
  owner: HouseId
): GroundUnit =
  ## Create a Marine unit (invasion force) from config
  ## Stats loaded from config/ground_units.toml

  let cfg = globalGroundUnitsConfig.marine_division

  result = GroundUnit(
    unitType: GroundUnitType.Marine,
    id: id,
    owner: owner,
    attackStrength: cfg.attack_strength,
    defenseStrength: cfg.defense_strength,
    state: CombatState.Undamaged
  )

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
