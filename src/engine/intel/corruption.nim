## Intelligence Corruption
##
## Centralized module for applying disinformation corruption to intelligence reports
## Per espionage PlantDisinformation action - corrupts intel with 20-40% variance
##
## **Architecture Role:** Business logic utility
## - Operates on intel report values in-place
## - No state access needed (pure data transformation)

import std/[random, options]
import ../types/[core, player_state, espionage]

## Corruption Detection

proc hasIntelCorruption*(
    effects: seq[OngoingEffect], targetHouse: HouseId
): Option[OngoingEffect] =
  ## Check if a house has active intelligence corruption
  ## Returns the corruption effect if active
  for effect in effects:
    if effect.effectType == EffectType.IntelCorrupted and
        effect.targetHouse == targetHouse and effect.turnsRemaining > 0:
      return some(effect)
  return none(OngoingEffect)

## Integer Corruption

proc corruptInt*(value: int32, magnitude: float, rng: var Rand): int32 =
  ## Corrupt an integer value by +/- magnitude percentage
  ## magnitude: 0.3 = +/- 30% variance
  ## Example: corruptInt(100, 0.3, rng) -> 70-130
  if value == 0:
    return 0

  # Random variance: -magnitude to +magnitude
  let variance = rng.rand(-magnitude .. magnitude)
  let corrupted = float(value) * (1.0 + variance)
  return max(0, int32(corrupted)) # Never go negative

proc corruptIntOption*(
    value: Option[int32], magnitude: float, rng: var Rand
): Option[int32] =
  ## Corrupt an optional integer value
  if value.isSome:
    return some(corruptInt(value.get(), magnitude, rng))
  return none(int32)

## Fleet Intelligence Corruption

proc corruptFleetObservation*(
    fleet: FleetObservation, magnitude: float, rng: var Rand
): FleetObservation =
  ## Corrupt fleet intelligence data
  result = fleet

  # Corrupt ship count
  result.shipCount = corruptInt(fleet.shipCount, magnitude, rng)

## Colony Intelligence Corruption

proc corruptColonyIntel*(
    colony: ColonyObservation, magnitude: float, rng: var Rand
): ColonyObservation =
  ## Corrupt colony intelligence data (ground/planetary assets)
  result = colony

  # Corrupt basic stats
  result.population = corruptInt(colony.population, magnitude, rng)
  result.infrastructure = corruptInt(colony.infrastructure, magnitude, rng)
  result.spaceportCount = corruptInt(colony.spaceportCount, magnitude, rng)
  result.armyCount = corruptInt(colony.armyCount, magnitude, rng)
  result.marineCount = corruptInt(colony.marineCount, magnitude, rng)
  result.groundBatteryCount = corruptInt(colony.groundBatteryCount, magnitude, rng)
  result.planetaryShieldLevel = corruptInt(colony.planetaryShieldLevel, magnitude, rng)

  # Corrupt economic intelligence
  result.grossOutput = corruptIntOption(colony.grossOutput, magnitude, rng)
  result.taxRevenue = corruptIntOption(colony.taxRevenue, magnitude, rng)

  # NOTE: constructionQueue NOT corrupted - too complex and disinformation would be obvious

## Orbital Intelligence Corruption

proc corruptOrbitalIntel*(
    orbital: OrbitalObservation, magnitude: float, rng: var Rand
): OrbitalObservation =
  ## Corrupt orbital intelligence data (space assets)
  result = orbital

  # Corrupt orbital asset counts
  result.starbaseCount = corruptInt(orbital.starbaseCount, magnitude, rng)
  result.shipyardCount = corruptInt(orbital.shipyardCount, magnitude, rng)
  result.drydockCount = corruptInt(orbital.drydockCount, magnitude, rng)
  result.reserveFleetCount = corruptInt(orbital.reserveFleetCount, magnitude, rng)
  result.mothballedFleetCount = corruptInt(orbital.mothballedFleetCount, magnitude, rng)

  # NOTE: IDs not corrupted - these are references (guardFleetIds, blockadeFleetIds, fighterSquadronIds)
  # Fleet and squadron details should be corrupted separately via FleetObservation/SquadronIntel reports

## Starbase Intelligence Corruption

proc corruptStarbaseIntel*(
    starbase: StarbaseObservation, magnitude: float, rng: var Rand
): StarbaseObservation =
  ## Corrupt starbase intelligence data (economic/R&D intel)
  result = starbase

  # Corrupt economic intelligence
  result.treasuryBalance = corruptIntOption(starbase.treasuryBalance, magnitude, rng)
  result.grossIncome = corruptIntOption(starbase.grossIncome, magnitude, rng)
  result.netIncome = corruptIntOption(starbase.netIncome, magnitude, rng)
  # Tax rate NOT corrupted - it's a policy setting, not measured data

  # Corrupt R&D intelligence
  if starbase.researchAllocations.isSome:
    let alloc = starbase.researchAllocations.get()
    result.researchAllocations = some(
      (
        erp: corruptInt(alloc.erp, magnitude, rng),
        srp: corruptInt(alloc.srp, magnitude, rng),
        trp: corruptInt(alloc.trp, magnitude, rng),
      )
    )

  # Tech levels NOT corrupted - these are discrete breakthrough levels, not measured quantities

## System Intelligence Corruption

proc corruptSystemIntel*(
    system: SystemObservation, magnitude: float, rng: var Rand
): SystemObservation =
  ## Corrupt system intelligence data (fleet sightings)
  result = system

  # NOTE: detectedFleetIds not corrupted - these are references
  # Fleet details should be corrupted separately via FleetObservation reports
  # System-level corruption is minimal - presence/absence data is hard to corrupt

