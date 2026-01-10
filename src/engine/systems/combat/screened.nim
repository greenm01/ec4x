## Screened Units System
##
## Handles units that do not participate in combat but are affected by outcomes.
## Per docs/specs/07-combat.md Section 7.6.1
##
## Screened units include:
## - Mothballed ships (offline, defenseless)
## - Auxiliary vessels (ETAC, TroopTransport - no combat capability)
## - Neoria facilities (spaceport, shipyard, drydock - orbital combat only)
##
## Rules:
## - Do NOT contribute AS/DS to combat
## - Retreat with their fleet if fleet retreats
## - Destroyed if their fleet is destroyed
## - Destroyed if defenders eliminated (orbital combat only)

import std/options
import ../../types/[core, game_state, ship, fleet, facilities, combat, colony]
import ../../state/[engine, iterators]

proc isAuxiliaryVessel*(shipClass: ShipClass): bool =
  ## Check if ship class is an auxiliary vessel (screened in combat)
  ## Per docs/specs/07-combat.md Section 7.6.1
  case shipClass
  of ShipClass.ETAC, ShipClass.TroopTransport:
    true
  else:
    false

proc isScreenedShip*(state: GameState, shipId: ShipId): bool =
  ## Check if ship is screened (does not participate in combat)
  ## Per docs/specs/07-combat.md Section 7.6.1
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return false

  let ship = shipOpt.get()

  # Check if auxiliary vessel
  if isAuxiliaryVessel(ship.shipClass):
    return true

  # Check if in mothballed fleet
  if ship.fleetId != FleetId(0):
    let fleetOpt = state.fleet(ship.fleetId)
    if fleetOpt.isSome:
      let fleet = fleetOpt.get()
      if fleet.status == FleetStatus.Mothballed:
        return true

  return false

proc getScreenedShipsInFleet*(state: GameState, fleetId: FleetId): seq[ShipId] =
  ## Get all screened ships in a fleet
  ## Per docs/specs/07-combat.md Section 7.6.1
  result = @[]

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return

  let fleet = fleetOpt.get()

  # If entire fleet is mothballed, all ships are screened
  if fleet.status == FleetStatus.Mothballed:
    return fleet.ships

  # Otherwise, only auxiliary vessels are screened
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if isAuxiliaryVessel(ship.shipClass):
        result.add(shipId)

proc getCombatShipsInFleet*(state: GameState, fleetId: FleetId): seq[ShipId] =
  ## Get all combat-capable ships in fleet (excludes screened units)
  ## Per docs/specs/07-combat.md Section 7.6.1
  result = @[]

  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return

  let fleet = fleetOpt.get()

  # If fleet is mothballed, no combat-capable ships
  if fleet.status == FleetStatus.Mothballed:
    return @[]

  # Filter out auxiliary vessels
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if not isAuxiliaryVessel(ship.shipClass):
        result.add(shipId)

proc getScreenedNeoriasAtColony*(
  state: GameState, colonyId: ColonyId
): seq[NeoriaId] =
  ## Get orbital Neoria facilities that are screened at colony
  ## Per docs/specs/07-combat.md Section 7.6.1
  ##
  ## Orbital facilities (shipyard, drydock) are screened during orbital combat
  ## and destroyed if defending fleet loses.
  ##
  ## Spaceports are planet-based and NOT auto-destroyed - only bombardment
  ## or invasion can destroy them.
  result = @[]

  # Only orbital neorias (Shipyard, Drydock) are screened
  # Spaceports are planet-based and survive orbital combat loss
  for neoria in state.neoriasAtColony(colonyId):
    if neoria.neoriaClass in [NeoriaClass.Shipyard, NeoriaClass.Drydock]:
      result.add(neoria.id)

proc destroyScreenedUnitsInFleet*(state: var GameState, fleetId: FleetId) =
  ## Destroy all screened units when fleet is destroyed
  ## Per docs/specs/07-combat.md Section 7.6.1
  ##
  ## Called when:
  ## - Fleet is destroyed in combat (all screened units destroyed)
  ##
  ## Note: Fleet retreat uses applyRetreatLossesToScreenedUnits() from
  ## retreat.nim which applies proportional losses based on escort casualties.

  let screenedShips = getScreenedShipsInFleet(state, fleetId)

  for shipId in screenedShips:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()
    ship.state = CombatState.Destroyed
    state.updateShip(shipId, ship)

proc destroyScreenedUnitsAtColony*(state: var GameState, colonyId: ColonyId) =
  ## Destroy screened units when colony defenders are eliminated in orbital combat
  ## Per docs/specs/07-combat.md Section 7.6.5
  ##
  ## Called when attackers win orbital combat:
  ## - Mothballed ships at colony destroyed
  ## - Auxiliary vessels at colony destroyed
  ## - Orbital neoria facilities destroyed (shipyard, drydock)
  ## - Spaceports are planet-based and NOT destroyed (survive orbital loss)
  ##
  ## Spaceports can only be destroyed by:
  ## - Bombardment (excess hits)
  ## - Invasion (auto-destroyed when marines land)
  ##
  ## Significant economic loss - defenders should evacuate before combat

  # Destroy all screened neorias
  let screenedNeorias = getScreenedNeoriasAtColony(state, colonyId)

  for neoriaId in screenedNeorias:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      continue

    var neoria = neoriaOpt.get()
    neoria.state = CombatState.Destroyed
    state.updateNeoria(neoriaId, neoria)

  # Destroy screened ships at colony (mothballed fleets, auxiliary vessels)
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()
  let systemId = colony.systemId

  # Find all fleets at the colony's system
  for fleetEntity in state.fleetsInSystem(systemId):
    # Case 1: Entire mothballed fleet - all ships destroyed
    if fleetEntity.status == FleetStatus.Mothballed:
      for shipId in fleetEntity.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          var ship = shipOpt.get()
          ship.state = CombatState.Destroyed
          state.updateShip(shipId, ship)

    # Case 2: Active fleet - destroy auxiliary vessels only
    else:
      for shipId in fleetEntity.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          if isAuxiliaryVessel(ship.shipClass):
            var updatedShip = ship
            updatedShip.state = CombatState.Destroyed
            state.updateShip(shipId, updatedShip)

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.6.1 - Orbital Combat Participants
## - docs/specs/07-combat.md Section 7.6.5 - Victory Conditions
##
## **Screened Unit Categories:**
## 1. **Mothballed ships**: Entire fleet offline, all ships screened
## 2. **Auxiliary vessels**: ETAC, TroopTransport (no combat capability)
## 3. **Neoria facilities**: Spaceport, shipyard, drydock (orbital combat only)
##
## **Screened Unit Lifecycle:**
## 1. Do NOT contribute AS/DS during combat (excluded from strength calculations)
## 2. Do NOT receive hits during combat (excluded from hit application)
## 3. Proportional losses during fleet retreat (see retreat.applyRetreatLossesToScreenedUnits)
## 4. Destroyed if fleet destroyed (see destroyScreenedUnitsInFleet)
## 5. Destroyed if defenders eliminated (orbital combat only, see destroyScreenedUnitsAtColony)
##
## **Strategic Implications:**
## - Defenders should evacuate auxiliary vessels before combat
## - Defenders should activate mothballed fleets or evacuate them
## - Losing orbital combat = losing all facilities (spaceport, shipyard, drydock)
## - High stakes for defending fortress colonies
##
## **Future Enhancements:**
## - Screened unit evacuation mechanics
## - Screened unit capture vs destruction (blitz operations)
