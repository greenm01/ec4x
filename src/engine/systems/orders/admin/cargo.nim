## Cargo Operations Administrative Commands
##
## This module contains the logic for executing zero-turn administrative commands
## related to cargo operations, specifically auto-loading marines and colonists.

import std/[tables, options, algorithm, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../squadron, ../../logger
import ../../economy/types as econ_types # For FacilityType
import ../../config/population_config # For soulsPerPtu
import ../main as orders # For OrderPacket (not directly used by autoLoadCargo, but good context)

proc autoLoadCargo*(state: var GameState, orders: Table[HouseId, orders.OrderPacket], events: var seq[resolution_types.GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## NOTE: Manual cargo operations now use zero-turn commands (executed before turn resolution)
  ## This auto-load only processes fleets that weren't manually managed

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modified = false

      for squadron in fleet.squadrons.mitems:
        # Only process Expansion/Auxiliary squadrons
        if squadron.squadronType notin {SquadronType.Expansion, SquadronType.Auxiliary}:
          continue

        # Skip crippled ships
        if squadron.flagship.isCrippled:
          continue

        # Skip ships already loaded
        if squadron.flagship.cargo.isSome:
          let cargo = squadron.flagship.cargo.get()
          if cargo.cargoType != CargoType.None:
            continue

        # Determine what cargo this ship can carry
        case squadron.flagship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available (capacity from config)
          if colony.marines > 0:
            let capacity = squadron.flagship.stats.carryLimit
            let loadAmount = min(capacity, colony.marines)
            squadron.flagship.cargo = some(ShipCargo(
              cargoType: CargoType.Marines,
              quantity: loadAmount,
              capacity: capacity
            ))
            colony.marines -= loadAmount
            modified = true
            logInfo(LogCategory.lcFleet, &"Auto-loaded {loadAmount} Marines onto {squadron.id} at {systemId}")

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + soulsPerPtu():
            let capacity = squadron.flagship.stats.carryLimit
            squadron.flagship.cargo = some(ShipCargo(
              cargoType: CargoType.Colonists,
              quantity: 1,
              capacity: capacity
            ))
            colony.souls -= soulsPerPtu()
            colony.population = colony.souls div 1_000_000
            modified = true
            logInfo(LogCategory.lcColonization, &"Auto-loaded 1 PTU onto {squadron.id} at {systemId}")

        else:
          discard  # Other ship classes don't have spacelift capability

      # Write back modified state if any cargo was loaded
      if modified:
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony
