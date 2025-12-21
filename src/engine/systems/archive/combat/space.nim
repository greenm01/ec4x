## Space Combat Resolution Mechanics
##
## This module encapsulates logic for space combat, including fleet engagements,
## raider detection, and diplomatic escalation based on combat outcomes.

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

proc applySpaceLiftScreeningLosses*(
  state: var GameState,
  combatOutcome: combat_engine.CombatResult,
  fleetsBeforeCombat: Table[FleetId, Fleet],
  combatPhase: string,  # "Space" or "Orbital"
  events: var seq[GameEvent]
) =
  ## Apply spacelift ship losses based on task force casualties
  ## Spacelift ships are screened by task forces - losses are proportional to task force casualties
  ## If task force destroyed → all spacelift ships destroyed
  ## If task force retreated → proportional spacelift ships destroyed (matching casualty %)

  # Track spacelift losses by house for event generation
  # Note: Spacelift ships are now in Expansion/Auxiliary squadrons - these are already
  # included in squadron casualty calculations, so we don't need separate spacelift loss logic.
  # However, we still track if these special squadrons were destroyed for event reporting.
  var spaceliftLossesByHouse: Table[HouseId, int] = initTable[HouseId, int]()

  for fleetId, fleetBefore in fleetsBeforeCombat.pairs:
    # Count Expansion/Auxiliary squadrons before
    var spaceliftSquadronsBefore = 0
    for squadron in fleetBefore.squadrons:
      if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
        spaceliftSquadronsBefore += 1

    if spaceliftSquadronsBefore == 0:
      continue  # No spacelift squadrons to lose

    # Skip mothballed fleets (they don't participate in combat, handled separately)
    if fleetBefore.status == FleetStatus.Mothballed:
      continue

    # Count Expansion/Auxiliary squadrons after
    var spaceliftSquadronsAfter = 0
    if fleetId in state.fleets:
      for squadron in state.fleets[fleetId].squadrons:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          spaceliftSquadronsAfter += 1

    # Track losses
    let spaceliftLosses = spaceliftSquadronsBefore - spaceliftSquadronsAfter
    if spaceliftLosses > 0:
      spaceliftLossesByHouse[fleetBefore.owner] = spaceliftLossesByHouse.getOrDefault(fleetBefore.owner, 0) + spaceliftLosses

      logCombat(&"{combatPhase} combat: Fleet {fleetId} transport squadron losses",
                "casualties=", $spaceliftLosses,
                "before=", $spaceliftSquadronsBefore,
                "after=", $spaceliftSquadronsAfter)

  # Generate events for transport squadron losses
  for houseId, losses in spaceliftLossesByHouse:
    events.add(event_factory.battle(
      houseId,
      combatOutcome.systemId,
      &"{combatPhase} combat: {losses} transport squadrons destroyed (screened by task force)"
    ))

proc isIntelOnlyFleet*(fleet: Fleet): bool =
  ## Check if fleet contains only Intel squadrons (intelligence gathering units)
  ## Intel-only fleets are invisible to combat fleets and never participate in combat
  if fleet.squadrons.len == 0:
    return false

  for squadron in fleet.squadrons:
    if squadron.squadronType != SquadronType.Intel:
      return false

  return true

proc getTargetBucket*(shipClass: ShipClass): TargetBucket =
  ## Determine target bucket from ship class
  ## Note: Starbases use TargetBucket.Starbase but aren't in ShipClass (they're facilities)
  case shipClass
  of ShipClass.Raider: TargetBucket.Raider
  of ShipClass.Fighter: TargetBucket.Fighter
  of ShipClass.Destroyer: TargetBucket.Destroyer
  else: TargetBucket.Capital

proc getStarbaseStats*(wepLevel: int): ShipStats =
  ## Load starbase combat stats from facilities.toml
  ## Applies WEP tech modifications like ships
  let facilityConfig = globalFacilitiesConfig.starbase

  # Base stats from facilities.toml
  var stats = ShipStats(
    name: "Starbase",
    class: "SB",
    role: ShipRole.SpecialWeapon,
    attackStrength: facilityConfig.attack_strength,
    defenseStrength: facilityConfig.defense_strength,
    commandCost: 0,  # Starbases don't consume command
    commandRating: 0,  # Starbases can't lead squadrons
    techLevel: facilityConfig.cst_min,
    buildCost: facilityConfig.build_cost,
    upkeepCost: facilityConfig.upkeep_cost,
    specialCapability: "",  # No special capabilities
    carryLimit: 0
  )

  # Apply WEP tech modifications (AS and DS scale with weapons tech)
  if wepLevel > 1:
    let weaponsMultiplier = pow(1.10, float(wepLevel - 1))
    stats.attackStrength = int(float(stats.attackStrength) * weaponsMultiplier)
    stats.defenseStrength = int(float(stats.defenseStrength) * weaponsMultiplier)

  return stats