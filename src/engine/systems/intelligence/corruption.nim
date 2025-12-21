## Intelligence Corruption
##
## Centralized module for applying disinformation corruption to intelligence reports
## Per espionage PlantDisinformation action - corrupts intel with 20-40% variance

import std/[random, options]
import ../../../common/types/core
import ../../types/espionage as esp_types
import ../../types/diplomacy as dip_types
import ../../config/diplomacy_config
import ../../types/intelligence as intel_types

## Corruption Detection

proc hasIntelCorruption*(effects: seq[esp_types.OngoingEffect], targetHouse: HouseId): Option[esp_types.OngoingEffect] =
  ## Check if a house has active intelligence corruption
  ## Returns the corruption effect if active
  for effect in effects:
    if effect.effectType == esp_types.EffectType.IntelCorrupted and
       effect.targetHouse == targetHouse and
       effect.turnsRemaining > 0:
      return some(effect)
  return none(esp_types.OngoingEffect)

## Integer Corruption

proc corruptInt*(value: int, magnitude: float, rng: var Rand): int =
  ## Corrupt an integer value by +/- magnitude percentage
  ## magnitude: 0.3 = +/- 30% variance
  ## Example: corruptInt(100, 0.3, rng) -> 70-130
  if value == 0:
    return 0

  # Random variance: -magnitude to +magnitude
  let variance = rng.rand(-magnitude..magnitude)
  let corrupted = float(value) * (1.0 + variance)
  return max(0, int(corrupted))  # Never go negative

proc corruptIntOption*(value: Option[int], magnitude: float, rng: var Rand): Option[int] =
  ## Corrupt an optional integer value
  if value.isSome:
    return some(corruptInt(value.get(), magnitude, rng))
  return none(int)

## Fleet Intelligence Corruption

proc corruptFleetIntel*(fleet: intel_types.FleetIntel, magnitude: float, rng: var Rand): intel_types.FleetIntel =
  ## Corrupt fleet intelligence data
  result = fleet

  # Corrupt ship count
  result.shipCount = corruptInt(fleet.shipCount, magnitude, rng)

  # Corrupt squadron details if present
  if fleet.squadronDetails.isSome:
    var corruptedSquadrons: seq[intel_types.SquadronIntel] = @[]
    for squadron in fleet.squadronDetails.get():
      var corruptedSquad = squadron
      corruptedSquad.shipCount = corruptInt(squadron.shipCount, magnitude, rng)
      corruptedSquad.techLevel = corruptInt(squadron.techLevel, magnitude, rng)
      corruptedSquad.hullIntegrity = corruptIntOption(squadron.hullIntegrity, magnitude, rng)
      corruptedSquadrons.add(corruptedSquad)
    result.squadronDetails = some(corruptedSquadrons)

## Colony Intelligence Corruption

proc corruptColonyIntel*(colony: intel_types.ColonyIntelReport, magnitude: float, rng: var Rand): intel_types.ColonyIntelReport =
  ## Corrupt colony intelligence data
  result = colony

  # Corrupt basic stats
  result.population = corruptInt(colony.population, magnitude, rng)
  result.industry = corruptInt(colony.industry, magnitude, rng)
  result.defenses = corruptInt(colony.defenses, magnitude, rng)
  result.starbaseLevel = corruptInt(colony.starbaseLevel, magnitude, rng)

  # Corrupt economic intelligence
  result.grossOutput = corruptIntOption(colony.grossOutput, magnitude, rng)
  result.taxRevenue = corruptIntOption(colony.taxRevenue, magnitude, rng)

  # Corrupt orbital defenses
  result.unassignedSquadronCount = corruptInt(colony.unassignedSquadronCount, magnitude, rng)
  result.reserveFleetCount = corruptInt(colony.reserveFleetCount, magnitude, rng)
  result.mothballedFleetCount = corruptInt(colony.mothballedFleetCount, magnitude, rng)
  result.shipyardCount = corruptInt(colony.shipyardCount, magnitude, rng)

  # NOTE: constructionQueue NOT corrupted - too complex and disinformation would be obvious

## Starbase Intelligence Corruption

proc corruptStarbaseIntel*(starbase: intel_types.StarbaseIntelReport, magnitude: float, rng: var Rand): intel_types.StarbaseIntelReport =
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
    result.researchAllocations = some((
      erp: corruptInt(alloc.erp, magnitude, rng),
      srp: corruptInt(alloc.srp, magnitude, rng),
      trp: corruptInt(alloc.trp, magnitude, rng)
    ))

  # Tech levels NOT corrupted - these are discrete breakthrough levels, not measured quantities

## System Intelligence Corruption

proc corruptSystemIntel*(system: intel_types.SystemIntelReport, magnitude: float, rng: var Rand): intel_types.SystemIntelReport =
  ## Corrupt system intelligence data (fleet sightings)
  result = system

  # Corrupt all fleet intel in system
  var corruptedFleets: seq[intel_types.FleetIntel] = @[]
  for fleet in system.detectedFleets:
    corruptedFleets.add(corruptFleetIntel(fleet, magnitude, rng))
  result.detectedFleets = corruptedFleets

## Scout Encounter Report Corruption

proc corruptScoutEncounter*(report: intel_types.ScoutEncounterReport, magnitude: float, rng: var Rand): intel_types.ScoutEncounterReport =
  ## Corrupt scout encounter report
  result = report

  # Corrupt fleet details if present
  if report.fleetDetails.len > 0:
    var corruptedFleets: seq[intel_types.FleetIntel] = @[]
    for fleet in report.fleetDetails:
      corruptedFleets.add(corruptFleetIntel(fleet, magnitude, rng))
    result.fleetDetails = corruptedFleets

  # Corrupt colony details if present
  if report.colonyDetails.isSome:
    result.colonyDetails = some(corruptColonyIntel(report.colonyDetails.get(), magnitude, rng))

  # NOTE: fleetMovements, description, significance NOT corrupted
