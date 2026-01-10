import std/options
import ./[core, ship]

type
  ZeroTurnCommandType* {.pure.} = enum
    ## Administrative commands that execute immediately (0 turns)
    ## All require fleet to be at friendly colony
    ## Execute during command submission phase, NOT turn resolution

    # Fleet reorganization (from FleetManagementCommand)
    DetachShips ## Split ships from fleet → create new fleet
    TransferShips ## Move ships between existing fleets
    MergeFleets ## Merge entire source fleet into target fleet

    # Cargo operations (from CargoManagementOrder)
    LoadCargo ## Load marines/colonists onto transport ships
    UnloadCargo ## Unload cargo from transport ships

    # Fighter operations (from FighterManagementOrder)
    LoadFighters ## Load fighter ships from colony to carrier
    UnloadFighters ## Unload fighter ships from carrier to colony
    TransferFighters ## Transfer fighter ships between carriers

    # Fleet status changes
    Reactivate ## Return Reserve/Mothballed fleet to Active status instantly

  ZeroTurnCommand* = object
    ## Immediate-execution administrative command
    ## Executes synchronously during command submission (NOT in OrderPacket)
    ## Returns immediate result (success/failure + error message)
    houseId*: HouseId
    commandType*: ZeroTurnCommandType

    # Context (varies by command type)
    colonySystem*: Option[SystemId] ## Colony where action occurs
    sourceFleetId*: Option[FleetId] ## Source fleet for fleet/cargo operations
    targetFleetId*: Option[FleetId] ## Target fleet for transfer/merge

    # Ship selection
    shipIndices*: seq[int] ## For ship selection (DetachShips, TransferShips)
    shipIds*: seq[ShipId] ## Direct ship IDs for operations

    # Cargo-specific
    cargoType*: Option[CargoClass] ## Type: Marines, Colonists
    cargoQuantity*: Option[int] ## Amount to load/unload (0 = all available)

    # Fighter-specific
    fighterIds*: seq[ShipId] ## Fighter ship IDs for operations
    carrierShipId*: Option[ShipId] ## Carrier ship ID (for Load/Unload)
    sourceCarrierShipId*: Option[ShipId] ## Source carrier (for TransferFighters)
    targetCarrierShipId*: Option[ShipId] ## Target carrier (for TransferFighters)

    # Fleet formation
    newFleetId*: Option[FleetId] ## Custom fleet ID for DetachShips

  ZeroTurnResult* = object ## Immediate result from zero-turn command execution
    success*: bool
    error*: string ## Human-readable error message

    # Optional result data
    newFleetId*: Option[FleetId] ## For DetachShips
    cargoLoaded*: int32 ## For LoadCargo (actual amount loaded)
    cargoUnloaded*: int32 ## For UnloadCargo (actual amount unloaded)
    fightersLoaded*: int32 ## For LoadFighters (ships loaded)
    fightersUnloaded*: int32 ## For UnloadFighters (ships unloaded)
    fightersTransferred*: int32 ## For TransferFighters (ships transferred)
    warnings*: seq[string] ## Non-fatal issues

  ValidationResult* = object ## Validation result (used internally)
    valid*: bool
    error*: string


