import unittest
import std/[options]
import ../../src/daemon/parser/kdl_orders
import ../../src/engine/types/[command, fleet, core, production]

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
