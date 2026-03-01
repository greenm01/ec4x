import unittest
import std/[options]
import ../../src/daemon/parser/kdl_commands
import ../../src/engine/types/[command, fleet, production, zero_turn, ship]

test "Parse Fleet Command":
  let kdl = """
    orders turn=1 house=(HouseId)1 {
      fleet (FleetId)101 hold
      fleet (FleetId)102 {
        move to=(SystemId)5 roe=8
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.turn == 1
  check packet.houseId.int == 1
  check packet.fleetCommands.len == 2
  check packet.fleetCommands[0].commandType == FleetCommandType.Hold
  check packet.fleetCommands[0].fleetId.int == 101
  check packet.fleetCommands[1].commandType == FleetCommandType.Move
  check packet.fleetCommands[1].fleetId.int == 102
  check packet.fleetCommands[1].targetSystem.get().int == 5
  check packet.fleetCommands[1].roe.get() == 8

test "Parse Build Command":
  let kdl = """
    orders turn=5 house=(HouseId)2 {
      build (ColonyId)10 {
        ship corvette quantity=2
        facility shipyard
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.houseId.int == 2
  check packet.buildCommands.len == 2
  
  let cmd1 = packet.buildCommands[0]
  check cmd1.colonyId.int == 10
  check cmd1.buildType == BuildType.Ship
  check cmd1.quantity == 2
  # check cmd1.shipClass.get() == ShipClass.Corvette # Needs import ship
  
  let cmd2 = packet.buildCommands[1]
  check cmd2.colonyId.int == 10
  check cmd2.buildType == BuildType.Facility
  check cmd2.quantity == 1

test "Parse ZTC - DetachShips with shipIds":
  let kdl = """
    orders house=(HouseId)1 turn=11 {
      zero-turn {
        detach-ships source=(FleetId)4 {
          ship (ShipId)10
          ship (ShipId)14
        }
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  let ztc = packet.zeroTurnCommands[0]
  check ztc.commandType == ZeroTurnCommandType.DetachShips
  check ztc.houseId.int == 1
  check ztc.sourceFleetId.get().int == 4
  check ztc.targetFleetId.isNone
  check ztc.newFleetId.isNone
  check ztc.shipIds.len == 2
  check ztc.shipIds[0].int == 10
  check ztc.shipIds[1].int == 14
  check ztc.shipIndices.len == 0

test "Parse ZTC - DetachShips with new-fleet temp ID":
  let kdl = """
    orders house=(HouseId)1 turn=11 {
      zero-turn {
        detach-ships source=(FleetId)4 new-fleet=(FleetId)999 {
          ship (ShipId)10
        }
      }
      fleet (FleetId)999 {
        colonize to=(SystemId)30
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  check packet.zeroTurnCommands[0].newFleetId.get().int == 999
  check packet.fleetCommands.len == 1
  check packet.fleetCommands[0].fleetId.int == 999
  check packet.fleetCommands[0].commandType == FleetCommandType.Colonize

test "Parse ZTC - TransferShips":
  let kdl = """
    orders house=(HouseId)2 turn=5 {
      zero-turn {
        transfer-ships source=(FleetId)3 target=(FleetId)7 {
          ship (ShipId)20
          ship (ShipId)21
        }
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  let ztc = packet.zeroTurnCommands[0]
  check ztc.commandType == ZeroTurnCommandType.TransferShips
  check ztc.sourceFleetId.get().int == 3
  check ztc.targetFleetId.get().int == 7
  check ztc.shipIds.len == 2
  check ztc.shipIds[0].int == 20

test "Parse ZTC - MergeFleets":
  let kdl = """
    orders house=(HouseId)1 turn=3 {
      zero-turn {
        merge-fleets source=(FleetId)5 target=(FleetId)2
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  let ztc = packet.zeroTurnCommands[0]
  check ztc.commandType == ZeroTurnCommandType.MergeFleets
  check ztc.sourceFleetId.get().int == 5
  check ztc.targetFleetId.get().int == 2
  check ztc.shipIds.len == 0

test "Parse ZTC - Reactivate":
  let kdl = """
    orders house=(HouseId)1 turn=7 {
      zero-turn {
        reactivate source=(FleetId)8
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  let ztc = packet.zeroTurnCommands[0]
  check ztc.commandType == ZeroTurnCommandType.Reactivate
  check ztc.sourceFleetId.get().int == 8

test "Parse ZTC - LoadCargo and UnloadCargo":
  let kdl = """
    orders house=(HouseId)1 turn=9 {
      zero-turn {
        load-cargo source=(FleetId)4 cargo="marines" quantity=5
        unload-cargo source=(FleetId)6
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 2
  let load = packet.zeroTurnCommands[0]
  check load.commandType == ZeroTurnCommandType.LoadCargo
  check load.sourceFleetId.get().int == 4
  check load.cargoType.get() == CargoClass.Marines
  check load.cargoQuantity.get() == 5
  let unload = packet.zeroTurnCommands[1]
  check unload.commandType == ZeroTurnCommandType.UnloadCargo
  check unload.sourceFleetId.get().int == 6

test "Parse ZTC - LoadFighters and UnloadFighters":
  let kdl = """
    orders house=(HouseId)1 turn=10 {
      zero-turn {
        load-fighters source=(FleetId)4 carrier=(ShipId)50 {
          fighter (ShipId)60
          fighter (ShipId)61
        }
        unload-fighters source=(FleetId)4 carrier=(ShipId)50 {
          fighter (ShipId)60
        }
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 2
  let load = packet.zeroTurnCommands[0]
  check load.commandType == ZeroTurnCommandType.LoadFighters
  check load.sourceFleetId.get().int == 4
  check load.carrierShipId.get().int == 50
  check load.fighterIds.len == 2
  check load.fighterIds[0].int == 60
  check load.fighterIds[1].int == 61
  let unload = packet.zeroTurnCommands[1]
  check unload.commandType == ZeroTurnCommandType.UnloadFighters
  check unload.fighterIds.len == 1

test "Parse ZTC - TransferFighters":
  let kdl = """
    orders house=(HouseId)1 turn=10 {
      zero-turn {
        transfer-fighters source=(FleetId)4 \
            source-carrier=(ShipId)50 target-carrier=(ShipId)55 {
          fighter (ShipId)62
        }
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 1
  let ztc = packet.zeroTurnCommands[0]
  check ztc.commandType == ZeroTurnCommandType.TransferFighters
  check ztc.sourceFleetId.get().int == 4
  check ztc.sourceCarrierShipId.get().int == 50
  check ztc.targetCarrierShipId.get().int == 55
  check ztc.fighterIds.len == 1
  check ztc.fighterIds[0].int == 62

test "Parse ZTC - Multiple commands in one block":
  let kdl = """
    orders house=(HouseId)1 turn=11 {
      zero-turn {
        merge-fleets source=(FleetId)3 target=(FleetId)4
        reactivate source=(FleetId)9
        detach-ships source=(FleetId)4 {
          ship (ShipId)100
        }
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands.len == 3
  check packet.zeroTurnCommands[0].commandType == ZeroTurnCommandType.MergeFleets
  check packet.zeroTurnCommands[1].commandType == ZeroTurnCommandType.Reactivate
  check packet.zeroTurnCommands[2].commandType == ZeroTurnCommandType.DetachShips

test "Parse ZTC - houseId propagated from root":
  let kdl = """
    orders house=(HouseId)2 turn=1 {
      zero-turn {
        reactivate source=(FleetId)1
      }
    }
  """
  let packet = parseOrdersString(kdl)
  check packet.zeroTurnCommands[0].houseId.int == 2
