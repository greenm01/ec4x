## Intelligence Corruption
##
## Centralized module for applying disinformation corruption to intelligence reports
## Per espionage PlantDisinformation action - corrupts intel with 20-40% variance
##
## **Architecture Role:** Business logic utility
## - Operates on intel report values in-place
## - No state access needed (pure data transformation)

import std/[random, options]
import ../types/[core, intel, espionage]

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

proc corruptFleetIntel*(
    fleet: FleetIntel, magnitude: float, rng: var Rand
): FleetIntel =
  ## Corrupt fleet intelligence data
  result = fleet

  # Corrupt ship count
  result.shipCount = corruptInt(fleet.shipCount, magnitude, rng)

  # Corrupt space-lift ship count if present
  result.spaceLiftShipCount = corruptIntOption(fleet.spaceLiftShipCount, magnitude, rng)

  # NOTE: squadronIds not corrupted - these are references, not measured data
  # Squadron details should be corrupted separately via SquadronIntel reports

## Squadron Intelligence Corruption

proc corruptSquadronIntel*(
    squadron: SquadronIntel, magnitude: float, rng: var Rand
): SquadronIntel =
  ## Corrupt squadron intelligence data
  result = squadron

  # Corrupt ship count and tech level
  result.shipCount = corruptInt(squadron.shipCount, magnitude, rng)
  result.techLevel = corruptInt(squadron.techLevel, magnitude, rng)
  result.hullIntegrity = corruptIntOption(squadron.hullIntegrity, magnitude, rng)

  # NOTE: squadronId and shipClass not corrupted - these are identifiers

## Colony Intelligence Corruption

proc corruptColonyIntel*(
    colony: ColonyIntelReport, magnitude: float, rng: var Rand
): ColonyIntelReport =
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
    orbital: OrbitalIntelReport, magnitude: float, rng: var Rand
): OrbitalIntelReport =
  ## Corrupt orbital intelligence data (space assets)
  result = orbital

  # Corrupt orbital asset counts
  result.starbaseCount = corruptInt(orbital.starbaseCount, magnitude, rng)
  result.shipyardCount = corruptInt(orbital.shipyardCount, magnitude, rng)
  result.drydockCount = corruptInt(orbital.drydockCount, magnitude, rng)
  result.reserveFleetCount = corruptInt(orbital.reserveFleetCount, magnitude, rng)
  result.mothballedFleetCount = corruptInt(orbital.mothballedFleetCount, magnitude, rng)

  # NOTE: IDs not corrupted - these are references (guardFleetIds, blockadeFleetIds, fighterSquadronIds)
  # Fleet and squadron details should be corrupted separately via FleetIntel/SquadronIntel reports

## Starbase Intelligence Corruption

proc corruptStarbaseIntel*(
    starbase: StarbaseIntelReport, magnitude: float, rng: var Rand
): StarbaseIntelReport =
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
    system: SystemIntelReport, magnitude: float, rng: var Rand
): SystemIntelReport =
  ## Corrupt system intelligence data (fleet sightings)
  result = system

  # NOTE: detectedFleetIds not corrupted - these are references
  # Fleet details should be corrupted separately via FleetIntel reports
  # System-level corruption is minimal - presence/absence data is hard to corrupt

## Scout Encounter Report Corruption

proc corruptScoutEncounter*(
    report: ScoutEncounterReport, magnitude: float, rng: var Rand
): ScoutEncounterReport =
  ## Corrupt scout encounter report
  result = report

  # NOTE: observedFleetIds and colonyId not corrupted - these are references
  # Fleet and colony details should be corrupted separately via their intel reports
  # Scout encounters primarily record presence/movement which is hard to corrupt

  # Significance could be corrupted to make events seem more/less important
  result.significance = corruptInt(report.significance, magnitude, rng)

  # NOTE: fleetMovements, description, observedHouses NOT corrupted
  # These are observational data that's difficult to misreport convincingly
