## Orbital Combat Resolution Mechanics
##
## This module encapsulates logic for orbital combat, including engagements with
## starbases, unassigned squadrons, and ground forces that can defend from orbit.

import std/[tables, options, sequtils, hashes, math, random, strformat]
import ../../common/[logger as common_logger, types/core, types/combat,
                    types/units]
import ../../gamestate, ../../index_maintenance, ../../logger, ../../orders, ../../fleet,
       ../../squadron
import ../engine as combat_engine # Core combat engine
import ../types as combat_types    # Combat-specific types
import ../../systems/economy/[types as econ_types, facility_damage]
import ../../systems/prestige/main as prestige
import ../../config/[prestige_multiplier, prestige_config, facilities_config]
import ../../types/diplomacy as dip_types
import ../../systems/diplomacy/engine as dip_engine
import ../../systems/intelligence/diplomatic_intel
import ../../types/resolution # Common resolution types
import ../../fleet_orders # For findClosestOwnedColony, resolveMovementOrder
import ../../systems/events/event_factory/init as event_factory
import ../../systems/intelligence/[types as intel_types, combat_intel]
import ./space # For executeCombat, autoEscalateDiplomacy, processCombatEvents

proc resolveOrbitalCombat*(
  state: var GameState,
  systemId: SystemId,
  orbitalDefenders: seq[(FleetId, Fleet)],
  survivingAttackerFleets: seq[(FleetId, Fleet)],
  systemOwner: Option[HouseId],
  events: var seq[GameEvent],
  combatReports: var seq[CombatReport],
  rng: var Rand,
  preDetectedHouses: seq[HouseId] = @[]
): tuple[outcome: CombatResult, fleetsAtSystem: seq[(FleetId, Fleet)]] =
  ## Resolve orbital combat at a system.
  ## Orbital defenders = guard fleets + reserve + starbases + unassigned squadrons.

  logCombat("Phase 2: Orbital Combat")

  # Combine orbital defenders and surviving attackers
  var orbitalFleets = orbitalDefenders & survivingAttackerFleets

  # INTELLIGENCE GATHERING: Pre-Combat Reports (Orbital Phase)
  # Each house generates detailed intel on EACH other house's orbital forces
  var orbitalHouses: seq[HouseId] = @[]
  for (fleetId, fleet) in orbitalFleets:
    if fleet.owner notin orbitalHouses:
      orbitalHouses.add(fleet.owner)

  # Generate separate reports for each house observing each other house
  for reportingHouse in orbitalHouses:
    var alliedFleetIds: seq[FleetId] = @[]

    # Collect own forces
    for (fleetId, fleet) in orbitalFleets:
      if fleet.owner == reportingHouse:
        alliedFleetIds.add(fleetId)

    # Generate separate intel report for EACH other house
    for otherHouse in orbitalHouses:
      if otherHouse == reportingHouse:
        continue  # Don't report on yourself

      var otherHouseFleetIds: seq[FleetId] = @[]
      for (fleetId, fleet) in orbitalFleets:
        if fleet.owner == otherHouse:
          otherHouseFleetIds.add(fleetId)

      if otherHouseFleetIds.len > 0:
        let orbitalPreCombatReport = combat_intel.generatePreCombatReport(
          state, systemId, intel_types.CombatPhase.Orbital,
          reportingHouse, alliedFleetIds, otherHouseFleetIds
        )
        # CRITICAL: Get, modify, write back to persist
        var house = state.houses[reportingHouse]
        house.intelligence.addCombatReport(orbitalPreCombatReport)
        state.houses[reportingHouse] = house

  let (outcome, fleets, detected) = space.executeCombat(
    state, systemId, orbitalFleets, systemOwner,
    includeStarbases = true,
    includeUnassignedSquadrons = true,
    "Orbital Combat",
    events,
    preDetectedHouses = preDetectedHouses  # Pass detection status from space combat
  )

  logCombat("Orbital combat complete", "rounds=", $outcome.totalRounds)

  space.autoEscalateDiplomacy(state, outcome, "Orbital Combat", fleets)

  # Generate combat narrative events for orbital combat (Phase 7a)
  space.processCombatEvents(state, systemId, outcome, "OrbitalCombat", events)

  return (outcome, fleets)
