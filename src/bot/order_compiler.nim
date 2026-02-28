## Compile strict bot order draft into canonical CommandPacket.

import std/[options, strutils, tables, sets]

import ./order_schema
import ../engine/types/[core, fleet, ship, production, facilities,
  ground_unit, colony, command, tech]

type
  BotCompileResult* = object
    ok*: bool
    packet*: CommandPacket
    errors*: seq[string]

proc normalizeToken(token: string): string =
  result = ""
  for ch in token.toLowerAscii():
    if ch in {'a' .. 'z'} or ch in {'0' .. '9'}:
      result.add(ch)

proc parseFleetCommandType(token: string): Option[FleetCommandType] =
  case normalizeToken(token)
  of "hold": some(FleetCommandType.Hold)
  of "move": some(FleetCommandType.Move)
  of "seekhome": some(FleetCommandType.SeekHome)
  of "patrol": some(FleetCommandType.Patrol)
  of "guardstarbase": some(FleetCommandType.GuardStarbase)
  of "guardcolony": some(FleetCommandType.GuardColony)
  of "blockade": some(FleetCommandType.Blockade)
  of "bombard": some(FleetCommandType.Bombard)
  of "invade": some(FleetCommandType.Invade)
  of "blitz": some(FleetCommandType.Blitz)
  of "colonize": some(FleetCommandType.Colonize)
  of "scoutcolony": some(FleetCommandType.ScoutColony)
  of "scoutsystem": some(FleetCommandType.ScoutSystem)
  of "hackstarbase": some(FleetCommandType.HackStarbase)
  of "joinfleet": some(FleetCommandType.JoinFleet)
  of "rendezvous": some(FleetCommandType.Rendezvous)
  of "salvage": some(FleetCommandType.Salvage)
  of "reserve": some(FleetCommandType.Reserve)
  of "mothball": some(FleetCommandType.Mothball)
  of "view": some(FleetCommandType.View)
  else: none(FleetCommandType)

proc parseBuildType(token: string): Option[BuildType] =
  case normalizeToken(token)
  of "ship": some(BuildType.Ship)
  of "facility": some(BuildType.Facility)
  of "ground": some(BuildType.Ground)
  of "industrial": some(BuildType.Industrial)
  of "infrastructure": some(BuildType.Infrastructure)
  else: none(BuildType)

proc parseShipClass(token: string): Option[ShipClass] =
  case normalizeToken(token)
  of "corvette": some(ShipClass.Corvette)
  of "frigate": some(ShipClass.Frigate)
  of "destroyer": some(ShipClass.Destroyer)
  of "lightcruiser": some(ShipClass.LightCruiser)
  of "cruiser": some(ShipClass.Cruiser)
  of "battlecruiser": some(ShipClass.Battlecruiser)
  of "battleship": some(ShipClass.Battleship)
  of "dreadnought": some(ShipClass.Dreadnought)
  of "superdreadnought": some(ShipClass.SuperDreadnought)
  of "carrier": some(ShipClass.Carrier)
  of "supercarrier": some(ShipClass.SuperCarrier)
  of "raider": some(ShipClass.Raider)
  of "scout": some(ShipClass.Scout)
  of "etac": some(ShipClass.ETAC)
  of "trooptransport": some(ShipClass.TroopTransport)
  of "fighter": some(ShipClass.Fighter)
  of "planetbreaker": some(ShipClass.PlanetBreaker)
  else: none(ShipClass)

proc parseFacilityClass(token: string): Option[FacilityClass] =
  case normalizeToken(token)
  of "shipyard": some(FacilityClass.Shipyard)
  of "spaceport": some(FacilityClass.Spaceport)
  of "drydock": some(FacilityClass.Drydock)
  of "starbase": some(FacilityClass.Starbase)
  else: none(FacilityClass)

proc parseGroundClass(token: string): Option[GroundClass] =
  case normalizeToken(token)
  of "army": some(GroundClass.Army)
  of "marine": some(GroundClass.Marine)
  of "groundbattery": some(GroundClass.GroundBattery)
  of "planetaryshield": some(GroundClass.PlanetaryShield)
  else: none(GroundClass)

proc parseTechField(token: string): Option[TechField] =
  case normalizeToken(token)
  of "cst": some(TechField.ConstructionTech)
  of "wep": some(TechField.WeaponsTech)
  of "ter": some(TechField.TerraformingTech)
  of "eli": some(TechField.ElectronicIntelligence)
  of "clk": some(TechField.CloakingTech)
  of "sld": some(TechField.ShieldTech)
  of "cic": some(TechField.CounterIntelligence)
  of "stl": some(TechField.StrategicLiftTech)
  of "fc": some(TechField.FlagshipCommandTech)
  of "sc": some(TechField.StrategicCommandTech)
  of "fd": some(TechField.FighterDoctrine)
  of "aco": some(TechField.AdvancedCarrierOps)
  else: none(TechField)

proc commandNeedsSystemTarget(commandType: FleetCommandType): bool =
  commandType in {
    FleetCommandType.Move,
    FleetCommandType.Patrol,
    FleetCommandType.GuardStarbase,
    FleetCommandType.GuardColony,
    FleetCommandType.Blockade,
    FleetCommandType.Bombard,
    FleetCommandType.Invade,
    FleetCommandType.Blitz,
    FleetCommandType.Colonize,
    FleetCommandType.ScoutColony,
    FleetCommandType.ScoutSystem,
    FleetCommandType.HackStarbase,
    FleetCommandType.Rendezvous,
    FleetCommandType.View
  }

proc compileCommandPacket*(draft: BotOrderDraft): BotCompileResult =
  var errors: seq[string] = @[]
  var research = ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int32]()
  )

  if draft.researchAllocation.isSome:
    let alloc = draft.researchAllocation.get()
    if alloc.economic.isSome:
      research.economic = int32(alloc.economic.get())
    if alloc.science.isSome:
      research.science = int32(alloc.science.get())
    for key, value in alloc.fields.pairs:
      let field = parseTechField(key)
      if field.isNone:
        errors.add("Unknown research field: " & key)
      else:
        research.technology[field.get()] = int32(value)

  var packet = CommandPacket(
    houseId: HouseId(draft.houseId),
    turn: int32(draft.turn),
    zeroTurnCommands: @[],
    fleetCommands: @[],
    buildCommands: @[],
    repairCommands: @[],
    scrapCommands: @[],
    researchAllocation: research,
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    espionageActions: @[],
    ebpInvestment: int32(draft.ebpInvestment.get(0)),
    cipInvestment: int32(draft.cipInvestment.get(0))
  )

  var seenFleetIds = initHashSet[int]()
  for order in draft.fleetCommands:
    if order.fleetId in seenFleetIds:
      errors.add("Duplicate fleet command for fleet " & $order.fleetId)
      continue
    seenFleetIds.incl(order.fleetId)

    let cmdTypeOpt = parseFleetCommandType(order.commandType)
    if cmdTypeOpt.isNone:
      errors.add("Unknown fleet command type: " & order.commandType)
      continue
    let cmdType = cmdTypeOpt.get()

    if commandNeedsSystemTarget(cmdType) and order.targetSystemId.isNone:
      errors.add("Missing targetSystemId for " & order.commandType)
      continue
    if cmdType == FleetCommandType.JoinFleet and order.targetFleetId.isNone:
      errors.add("Missing targetFleetId for join-fleet")
      continue
    if order.roe.isSome and (order.roe.get() < 0 or order.roe.get() > 10):
      errors.add("ROE out of range for fleet " & $order.fleetId)
      continue

    packet.fleetCommands.add(FleetCommand(
      fleetId: FleetId(order.fleetId),
      commandType: cmdType,
      targetSystem:
        if order.targetSystemId.isSome:
          some(SystemId(order.targetSystemId.get()))
        else:
          none(SystemId),
      targetFleet:
        if order.targetFleetId.isSome:
          some(FleetId(order.targetFleetId.get()))
        else:
          none(FleetId),
      priority: 0,
      roe:
        if order.roe.isSome:
          some(int32(order.roe.get()))
        else:
          none(int32)
    ))

  for order in draft.buildCommands:
    let buildTypeOpt = parseBuildType(order.buildType)
    if buildTypeOpt.isNone:
      errors.add("Unknown build type: " & order.buildType)
      continue

    var build = BuildCommand(
      colonyId: ColonyId(order.colonyId),
      buildType: buildTypeOpt.get(),
      quantity: int32(order.quantity.get(1)),
      shipClass: none(ShipClass),
      facilityClass: none(FacilityClass),
      groundClass: none(GroundClass),
      industrialUnits: int32(order.quantity.get(0))
    )

    case build.buildType
    of BuildType.Ship:
      if order.shipClass.isNone:
        errors.add("Ship build missing shipClass")
        continue
      let shipClass = parseShipClass(order.shipClass.get())
      if shipClass.isNone:
        errors.add("Unknown shipClass: " & order.shipClass.get())
        continue
      build.shipClass = shipClass
    of BuildType.Facility:
      if order.facilityClass.isNone:
        errors.add("Facility build missing facilityClass")
        continue
      let facClass = parseFacilityClass(order.facilityClass.get())
      if facClass.isNone:
        errors.add("Unknown facilityClass: " & order.facilityClass.get())
        continue
      build.facilityClass = facClass
      build.quantity = 1
    of BuildType.Ground:
      if order.groundClass.isNone:
        errors.add("Ground build missing groundClass")
        continue
      let groundClass = parseGroundClass(order.groundClass.get())
      if groundClass.isNone:
        errors.add("Unknown groundClass: " & order.groundClass.get())
        continue
      build.groundClass = groundClass
    of BuildType.Industrial:
      build.industrialUnits = int32(order.quantity.get(0))
    else:
      discard

    packet.buildCommands.add(build)

  for order in draft.populationTransfers:
    packet.populationTransfers.add(PopulationTransferCommand(
      houseId: HouseId(draft.houseId),
      sourceColony: ColonyId(order.sourceColonyId),
      destColony: ColonyId(order.destColonyId),
      ptuAmount: int32(order.ptuAmount)
    ))

  for order in draft.terraformCommands:
    packet.terraformCommands.add(TerraformCommand(
      houseId: HouseId(draft.houseId),
      colonyId: ColonyId(order.colonyId),
      startTurn: int32(draft.turn),
      turnsRemaining: 0,
      ppCost: 0,
      targetClass: 0
    ))

  for order in draft.colonyManagement:
    packet.colonyManagement.add(ColonyManagementCommand(
      colonyId: ColonyId(order.colonyId),
      autoRepair: order.autoRepair.get(false),
      autoLoadFighters: order.autoLoadFighters.get(false),
      autoLoadMarines: order.autoLoadMarines.get(false),
      taxRate:
        if order.taxRate.isSome:
          some(int32(order.taxRate.get()))
        else:
          none(int32)
    ))

  BotCompileResult(
    ok: errors.len == 0,
    packet: packet,
    errors: errors
  )
