## Repair Queue Management
##
## Handles automatic extraction of crippled ships from fleets and submission
## to repair queues at colonies with shipyard/spaceport capacity.
##
## Design:
## - Fleets with crippled ships at colonies automatically submit repair requests
## - Ships extracted from squadrons → repair queue (1 turn, 25% cost)
## - Repaired ships recommission through standard pipeline (squadron → fleet)
## - Construction projects take precedence over repairs for dock capacity

import std/[tables, options, strformat]
import ../gamestate
import ../fleet
import ../squadron
import types as econ_types
import ../logging
import ../../common/types/[core, units]
import ../assets

export econ_types.RepairProject, econ_types.FacilityType, econ_types.RepairTargetType

proc calculateRepairCost*(shipClass: ShipClass, facilityType: econ_types.FacilityType): int =
  ## Calculate repair cost for a ship at specific facility type
  ## Base cost: 25% of build cost (economy.md)
  ## Spaceport penalty: +50% cost (less efficient ground-based repairs)
  let stats = getShipStats(shipClass)
  let baseCost = (stats.constructionCost.float * 0.25).int

  case facilityType
  of econ_types.FacilityType.Shipyard:
    result = baseCost  # Standard 25% cost
  of econ_types.FacilityType.Spaceport:
    result = (baseCost.float * 1.5).int  # 50% more expensive (37.5% total)

proc determineRepairFacility*(shipClass: ShipClass): econ_types.FacilityType =
  ## Determine which facility type should handle repairs for a ship class
  ## Larger ships (BB, CA) require shipyards
  ## Smaller ships (CL, DD, FF, SC) can use spaceports
  case shipClass
  of ShipClass.Dreadnought, ShipClass.Battleship, ShipClass.SuperDreadnought,
     ShipClass.Carrier, ShipClass.HeavyCruiser, ShipClass.Cruiser:
    econ_types.FacilityType.Shipyard
  else:
    econ_types.FacilityType.Spaceport

proc extractCrippledShip*(state: var GameState, fleetId: FleetId,
                         squadronIdx: int, shipIdx: int): Option[RepairProject] =
  ## Extract a crippled ship from a fleet squadron and create repair project
  ## shipIdx: -1 for flagship, 0+ for escorts
  ## Returns None if extraction fails

  if fleetId notin state.fleets:
    return none(RepairProject)

  var fleet = state.fleets[fleetId]

  if squadronIdx < 0 or squadronIdx >= fleet.squadrons.len:
    return none(RepairProject)

  var squadron = fleet.squadrons[squadronIdx]

  # Extract ship based on index
  var shipClass: ShipClass
  var isCrippled: bool

  if shipIdx == -1:
    # Flagship
    shipClass = squadron.flagship.shipClass
    isCrippled = squadron.flagship.isCrippled

    if not isCrippled:
      return none(RepairProject)

    # TODO: Handle flagship extraction (need to dissolve squadron or transfer flagship)
    # For now, skip flagship repairs - this is a complex case
    return none(RepairProject)
  else:
    # Escort
    if shipIdx < 0 or shipIdx >= squadron.ships.len:
      return none(RepairProject)

    let ship = squadron.ships[shipIdx]
    shipClass = ship.shipClass
    isCrippled = ship.isCrippled

    if not isCrippled:
      return none(RepairProject)

    # Remove escort from squadron
    squadron.ships.delete(shipIdx)
    fleet.squadrons[squadronIdx] = squadron
    state.fleets[fleetId] = fleet

  # Create repair project
  let facilityType = determineRepairFacility(shipClass)
  let cost = calculateRepairCost(shipClass, facilityType)

  let repair = RepairProject(
    targetType: econ_types.RepairTargetType.Ship,
    facilityType: facilityType,
    fleetId: some(fleetId),
    squadronIdx: some(squadronIdx),
    shipIdx: some(shipIdx),
    starbaseIdx: none(int),
    shipClass: some(shipClass),
    cost: cost,
    turnsRemaining: 1,
    priority: 1  # Ship repairs = priority 1 (construction = 0, starbase = 2)
  )

  logInfo(LogCategory.lcEconomy,
          &"Extracted crippled {shipClass} from fleet-{fleetId} squad-{squadronIdx} " &
          &"for repair (cost: {cost} PP, facility: {facilityType})")

  return some(repair)

proc submitAutomaticStarbaseRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled starbases at colony
  ## Starbases always use shipyard facilities (priority 2, lower than ship repairs)

  if systemId notin state.colonies:
    return

  var colony = state.colonies[systemId]

  # Check if colony has shipyard (starbases require shipyard, not spaceport)
  let shipyardCapacity = colony.getShipyardDockCapacity()
  if shipyardCapacity == 0:
    return  # No shipyard available

  # Submit repairs for crippled starbases
  for idx, starbase in colony.starbases:
    if starbase.isCrippled:
      # Check if shipyard has capacity
      let activeProjects = colony.getActiveProjectsByFacility(econ_types.FacilityType.Shipyard)
      if activeProjects >= shipyardCapacity:
        logDebug(LogCategory.lcEconomy,
                 &"Colony-{systemId} has no shipyard capacity for starbase repair " &
                 &"({activeProjects}/{shipyardCapacity} docks used)")
        continue  # No capacity, skip this starbase

      # Calculate repair cost (25% of starbase build cost)
      # TODO: Get actual starbase build cost from config (for now use estimate)
      let starbaseBuildCost = 100  # Placeholder - starbases are expensive
      let repairCost = (starbaseBuildCost.float * 0.25).int

      let repair = RepairProject(
        targetType: econ_types.RepairTargetType.Starbase,
        facilityType: econ_types.FacilityType.Shipyard,
        fleetId: none(FleetId),
        squadronIdx: none(int),
        shipIdx: none(int),
        starbaseIdx: some(idx),
        shipClass: none(ShipClass),
        cost: repairCost,
        turnsRemaining: 1,
        priority: 2  # Starbase repairs = priority 2 (lowest)
      )

      colony.repairQueue.add(repair)
      logInfo(LogCategory.lcEconomy,
              &"Submitted repair for starbase-{starbase.id} at colony-{systemId} " &
              &"(cost: {repairCost} PP, shipyard)")

  # Update colony state
  state.colonies[systemId] = colony

proc submitAutomaticRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for fleets with crippled ships at this colony
  ## Called during turn resolution after fleet movements

  if systemId notin state.colonies:
    return

  var colony = state.colonies[systemId]

  # Check if colony has repair facilities
  let hasShipyard = colony.shipyards.len > 0
  let hasSpaceport = colony.spaceports.len > 0

  if not hasShipyard and not hasSpaceport:
    return  # No repair facilities

  # Submit starbase repairs first (they have lower priority but same facility)
  submitAutomaticStarbaseRepairs(state, systemId)

  # Reload colony after starbase repairs submitted
  colony = state.colonies[systemId]

  # Find all fleets at this colony
  var fleetsAtColony: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner == colony.owner:
      fleetsAtColony.add(fleetId)

  # Process each fleet, extracting crippled ships
  for fleetId in fleetsAtColony:
    let fleet = state.fleets[fleetId]

    # Check each squadron for crippled escorts (skip flagships for now)
    for squadronIdx in 0..<fleet.squadrons.len:
      let squadron = fleet.squadrons[squadronIdx]

      # Check escorts
      for shipIdx in 0..<squadron.ships.len:
        let ship = squadron.ships[shipIdx]
        if ship.isCrippled:
          # Check if colony has capacity for this repair
          let facilityType = determineRepairFacility(ship.shipClass)
          let activeProjects = colony.getActiveProjectsByFacility(facilityType)
          let capacity = case facilityType
            of econ_types.FacilityType.Shipyard: colony.getShipyardDockCapacity()
            of econ_types.FacilityType.Spaceport: colony.getSpaceportDockCapacity()

          if activeProjects >= capacity:
            logDebug(LogCategory.lcEconomy,
                     &"Colony-{systemId} has no {facilityType} capacity for repair " &
                     &"({activeProjects}/{capacity} docks used)")
            continue  # No capacity, skip this ship

          # Extract and add to repair queue
          let repairOpt = state.extractCrippledShip(fleetId, squadronIdx, shipIdx)
          if repairOpt.isSome:
            colony.repairQueue.add(repairOpt.get())
            logInfo(LogCategory.lcEconomy,
                    &"Submitted repair for {ship.shipClass} from fleet-{fleetId} " &
                    &"to colony-{systemId} {facilityType}")

  # Update colony state
  state.colonies[systemId] = colony
