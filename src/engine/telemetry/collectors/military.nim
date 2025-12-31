## @engine/telemetry/collectors/military.nim
##
## Collect military assets metrics from GameState.
## Covers: ship counts by class, squadron counts, ground unit counts.

import std/options
import ../../types/[telemetry, core, game_state, ship, squadron, colony]
import ../../state/[entity_manager, iterators, engine]

proc collectMilitaryMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect military asset counts from GameState
  result = prevMetrics # Start with previous metrics

  let houseOption = state.houses.entities.getEntity(houseId)
  if houseOption.isNone:
    return prevMetrics
  let house = houseOption.get()

  # ================================================================
  # MILITARY ASSETS - SHIPS (All 18 ship classes)
  # ================================================================
  # NOTE: Starbases are facilities (not ships), tracked in facilities.nim

  var fighterShips = 0i32
  var corvetteShips = 0i32
  var frigateShips = 0i32
  var scoutShips = 0i32
  var raiderShips = 0i32
  var destroyerShips = 0i32
  var lightCruiserShips = 0i32
  var cruiserShips = 0i32
  var battlecruiserShips = 0i32
  var battleshipShips = 0i32
  var dreadnoughtShips = 0i32
  var superDreadnoughtShips = 0i32
  var carrierShips = 0i32
  var superCarrierShips = 0i32
  var etacShips = 0i32
  var troopTransportShips = 0i32
  var planetBreakerShips = 0i32

  # Count colony-based fighters
  for colony in state.coloniesOwned(houseId):
    fighterShips += colony.fighterSquadronIds.len.int32

  # Planet-breakers tracked at house level
  planetBreakerShips = house.planetBreakerCount

  # Count fleet-based ships
  var idleCarrierCount = 0i32
  var totalCarrierCount = 0i32

  for squadron in state.squadronsOwned(houseId):
    if not squadron.destroyed:
      # Lookup flagship ship to check its class
      let flagshipOpt = state.ship(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        case flagship.shipClass
        of ShipClass.Fighter:
          fighterShips += 1
        of ShipClass.Corvette:
          corvetteShips += 1
        of ShipClass.Frigate:
          frigateShips += 1
        of ShipClass.Scout:
          scoutShips += 1
        of ShipClass.Raider:
          raiderShips += 1
        of ShipClass.Destroyer:
          destroyerShips += 1
        of ShipClass.LightCruiser:
          lightCruiserShips += 1
        of ShipClass.Cruiser:
          cruiserShips += 1
        of ShipClass.Battlecruiser:
          battlecruiserShips += 1
        of ShipClass.Battleship:
          battleshipShips += 1
        of ShipClass.Dreadnought:
          dreadnoughtShips += 1
        of ShipClass.SuperDreadnought:
          superDreadnoughtShips += 1
        of ShipClass.Carrier:
          carrierShips += 1
          totalCarrierCount += 1
          # TODO: Check embarked fighters when squadron type supports it
          # if squadron.embarkedFighters.len == 0:
          #   idleCarrierCount += 1
        of ShipClass.SuperCarrier:
          superCarrierShips += 1
          totalCarrierCount += 1
        of ShipClass.PlanetBreaker:
          planetBreakerShips += 1
        of ShipClass.ETAC:
          etacShips += 1
        of ShipClass.TroopTransport:
          troopTransportShips += 1

  # Assign ship counts
  result.fighterShips = fighterShips
  result.corvetteShips = corvetteShips
  result.frigateShips = frigateShips
  result.scoutShips = scoutShips
  result.raiderShips = raiderShips
  result.destroyerShips = destroyerShips
  result.lightCruiserShips = lightCruiserShips
  result.cruiserShips = cruiserShips
  result.battlecruiserShips = battlecruiserShips
  result.battleshipShips = battleshipShips
  result.dreadnoughtShips = dreadnoughtShips
  result.superDreadnoughtShips = superDreadnoughtShips
  result.carrierShips = carrierShips
  result.superCarrierShips = superCarrierShips
  result.etacShips = etacShips
  result.troopTransportShips = troopTransportShips
  result.planetBreakerShips = planetBreakerShips

  # Calculate total ships (18 ship classes, starbases are facilities)
  result.totalShips =
    fighterShips + corvetteShips + frigateShips + scoutShips + raiderShips +
    destroyerShips + lightCruiserShips + cruiserShips +
    battlecruiserShips + battleshipShips + dreadnoughtShips + superDreadnoughtShips +
    carrierShips + superCarrierShips + etacShips + troopTransportShips +
    planetBreakerShips

  # Logistics
  result.totalCarriers = totalCarrierCount
  result.idleCarriers = idleCarrierCount
  result.totalTransports = etacShips + troopTransportShips

  # ================================================================
  # MILITARY ASSETS - GROUND UNITS (All 4 ground unit types)
  # ================================================================

  var planetaryShieldUnits = 0i32
  var groundBatteryUnits = 0i32
  var armyUnits = 0i32
  var marinesAtColonies = 0i32
  var marinesOnTransports = 0i32

  # Count ground units at colonies
  for colony in state.coloniesOwned(houseId):
    if colony.planetaryShieldLevel > 0:
      planetaryShieldUnits += 1
    groundBatteryUnits += colony.groundBatteryIds.len.int32
    armyUnits += colony.armyIds.len.int32
    marinesAtColonies += colony.marineIds.len.int32

  for squadron in state.squadronsOwned(houseId):
    if squadron.squadronType == SquadronClass.Auxiliary:
      # Lookup flagship ship to check cargo
      let flagshipOpt = state.ship(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        if flagship.cargo.isSome:
          let cargo = flagship.cargo.get()
          if cargo.cargoType == CargoClass.Marines:
            marinesOnTransports += cargo.quantity

  result.planetaryShieldUnits = planetaryShieldUnits
  result.groundBatteryUnits = groundBatteryUnits
  result.armyUnits = armyUnits
  result.marinesAtColonies = marinesAtColonies
  result.marinesOnTransports = marinesOnTransports
  result.marineDivisionUnits = marinesAtColonies + marinesOnTransports

  # ================================================================
  # SCOUT MESH TRACKING (Intelligence support)
  # ================================================================

  var scoutCount = 0i32

  # Count scouts in squadrons
  for squadron in state.squadronsOwned(houseId):
    if not squadron.destroyed:
      # Check flagship
      let flagshipOpt = state.ship(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        if flagship.shipClass == ShipClass.Scout:
          scoutCount += 1
      # Count additional scout ships in squadron
      for shipId in squadron.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          if ship.shipClass == ShipClass.Scout:
            scoutCount += 1

  result.scoutCount = scoutCount

  # Total fighters (colony-based + fleet-based from earlier count)
  result.totalFighters = fighterShips
