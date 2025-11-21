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

const BombardmentCERTable* = [
  # Roll 0-2: 0.25× (round up)
  (minRoll: 0, maxRoll: 2, multiplier: 0.25),
  # Roll 3-5: 0.50× (round up)
  (minRoll: 3, maxRoll: 5, multiplier: 0.50),
  # Roll 6-8: 1.00×
  (minRoll: 6, maxRoll: 8, multiplier: 1.0),
  # Roll 9: 1.00× (critical - affects attackers only)
  (minRoll: 9, maxRoll: 9, multiplier: 1.0)
]

proc getBombardmentCER*(roll: int): (float, bool) =
  ## Get bombardment CER multiplier and critical hit flag
  ## Returns (multiplier, isCritical)
  for entry in BombardmentCERTable:
    if roll >= entry.minRoll and roll <= entry.maxRoll:
      let isCrit = (roll == 9)
      return (entry.multiplier, isCrit)
  # Fallback (should never happen)
  return (0.25, false)

## Ground Combat CER Table (Section 7.6)

const GroundCombatCERTable* = [
  # Roll 0-2: 0.50× (round up)
  (minRoll: 0, maxRoll: 2, multiplier: 0.5),
  # Roll 3-6: 1.00×
  (minRoll: 3, maxRoll: 6, multiplier: 1.0),
  # Roll 7-8: 1.50× (round up)
  (minRoll: 7, maxRoll: 8, multiplier: 1.5),
  # Roll 9: 2.00×
  (minRoll: 9, maxRoll: 9, multiplier: 2.0)
]

proc getGroundCombatCER*(roll: int): float =
  ## Get ground combat CER multiplier (invasion/blitz)
  for entry in GroundCombatCERTable:
    if roll >= entry.minRoll and roll <= entry.maxRoll:
      return entry.multiplier
  # Fallback
  return 0.5

## Planetary Shield Mechanics (Section 7.5.2)

const ShieldTable* = [
  # SLD Level, Chance%, D20 Roll Needed, % Blocked
  (level: 1, chance: 0.15, rollNeeded: 18, blockPct: 0.25),
  (level: 2, chance: 0.30, rollNeeded: 15, blockPct: 0.30),
  (level: 3, chance: 0.45, rollNeeded: 12, blockPct: 0.35),
  (level: 4, chance: 0.60, rollNeeded: 9, blockPct: 0.40),
  (level: 5, chance: 0.75, rollNeeded: 6, blockPct: 0.45),
  (level: 6, chance: 0.90, rollNeeded: 3, blockPct: 0.50)
]

proc rollShieldBlock*(shieldLevel: int, rng: var CombatRNG): (bool, float) =
  ## Roll to see if shields block damage
  ## Returns (blocked, percentage_to_block)
  ##
  ## Uses 1d20 roll (not 1d10) per spec

  if shieldLevel < 1 or shieldLevel > 6:
    return (false, 0.0)

  let shieldData = ShieldTable[shieldLevel - 1]

  # Roll 1d20 (extend RNG to support d20)
  # TODO: Add roll1d20() to CER module
  let roll = (rng.roll1d10() * 2) mod 20 + 1  # TEMP: Simulate d20

  if roll >= shieldData.rollNeeded:
    return (true, shieldData.blockPct)
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
  ##
  ## TODO M3: Implement full bombardment mechanics
  ## TODO M3: Handle Planet-Breaker shield bypass
  ## TODO M3: Apply damage to ground batteries
  ## TODO M3: Handle excess damage to ground forces and infrastructure
  ## TODO M3: Implement critical hit rules (attacker only)

  result = BombardmentResult()
  echo "STUB: Bombardment not yet implemented"

proc conductBombardment*(
  attackingFleet: seq[CombatSquadron],
  defense: var PlanetaryDefense,
  seed: int64,
  maxRounds: int = 3
): BombardmentResult =
  ## Conduct full bombardment (up to 3 rounds per turn)
  ##
  ## TODO M3: Implement multi-round bombardment
  ## TODO M3: Track cumulative damage
  ## TODO M3: Stop early if all batteries destroyed

  var rng = initRNG(seed)
  result = resolveBombardmentRound(attackingFleet, defense, rng)
  result.roundsCompleted = 1

## Planetary Invasion (Section 7.6.1)

proc conductInvasion*(
  attackingForces: seq[GroundUnit],
  defendingForces: seq[GroundUnit],
  defense: var PlanetaryDefense,
  seed: int64
): InvasionResult =
  ## Conduct planetary invasion
  ##
  ## Prerequisites:
  ## 1. All ground batteries must be destroyed (via bombardment first)
  ## 2. Marines must be present in attacking forces
  ##
  ## Effects on success:
  ## - Shields and spaceports destroyed immediately
  ## - 50% of remaining IU destroyed by loyal citizens
  ##
  ## TODO M3: Implement ground combat resolution
  ## TODO M3: Apply destruction protection rules to ground units
  ## TODO M3: Handle multi-round combat until one side eliminated
  ## TODO M3: Calculate infrastructure destruction (50% IU)

  result = InvasionResult()
  result.success = false
  echo "STUB: Invasion not yet implemented"

## Planetary Blitz (Section 7.6.2)

proc conductBlitz*(
  attackingFleet: seq[CombatSquadron],
  attackingForces: seq[GroundUnit],
  defense: var PlanetaryDefense,
  seed: int64
): InvasionResult =
  ## Conduct planetary blitz (fast insertion)
  ##
  ## Differences from invasion:
  ## 1. One round vs ground batteries (transports can be destroyed)
  ## 2. Marines get 0.5× AS modifier (quick insertion penalty)
  ## 3. No IU destroyed on success (assets seized intact)
  ## 4. Shields, spaceports, batteries seized if successful
  ##
  ## TODO M3: Implement blitz mechanics
  ## TODO M3: Handle transport vulnerability during insertion
  ## TODO M3: Apply Marine AS penalty (× 0.5)
  ## TODO M3: Asset seizure on success

  result = InvasionResult()
  result.success = false
  echo "STUB: Blitz not yet implemented"

## Ground Unit Management

proc createGroundBattery*(
  id: string,
  owner: HouseId,
  techLevel: int = 1
): GroundUnit =
  ## Create a ground battery unit
  ## Per reference.md:9.1 - Ground Battery has AS=0, DS=8, Cost=100 PP
  ##
  ## TODO M3: Load stats from config
  ## TODO M3: Apply tech modifiers if applicable

  result = GroundUnit(
    unitType: GroundUnitType.GroundBattery,
    id: id,
    owner: owner,
    attackStrength: 0,  # Ground batteries don't attack (defense only)
    defenseStrength: 8,
    state: CombatState.Undamaged
  )

proc createArmy*(
  id: string,
  owner: HouseId
): GroundUnit =
  ## Create an Army unit (garrison defense)
  ## Per reference.md:9.2 - Army has AS=5, DS=2, Cost=20 PP
  ##
  ## TODO M3: Load stats from config

  result = GroundUnit(
    unitType: GroundUnitType.Army,
    id: id,
    owner: owner,
    attackStrength: 5,
    defenseStrength: 2,
    state: CombatState.Undamaged
  )

proc createMarine*(
  id: string,
  owner: HouseId
): GroundUnit =
  ## Create a Marine unit (invasion force)
  ## Per reference.md:9.2 - Marine has AS=7, DS=2, Cost=30 PP
  ##
  ## TODO M3: Load stats from config

  result = GroundUnit(
    unitType: GroundUnitType.Marine,
    id: id,
    owner: owner,
    attackStrength: 7,
    defenseStrength: 2,
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
