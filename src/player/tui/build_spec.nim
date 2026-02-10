## Build spec tables for TUI build modal.
## Values loaded from KDL at compile time via nimkdl.

import std/[options, math, os]
import kdl

import ../sam/tui_model
import ../../engine/types/[ship, ground_unit, facilities]

type
  ShipSpecRow* = object
    shipClass*: ShipClass
    code*: string
    name*: string
    cst*: int
    pc*: int
    mcPct*: int
    attack*: int
    defense*: int
    command*: int
    carry*: int

  GroundSpecRow* = object
    groundClass*: GroundClass
    code*: string
    name*: string
    cst*: int
    pc*: int
    mcPct*: int
    attack*: int
    defense*: int

  FacilitySpecRow* = object
    facilityClass*: FacilityClass
    code*: string
    name*: string
    cst*: int
    pc*: int
    mcPct*: int
    attack*: int
    defense*: int
    docks*: int
    time*: int

type
  SpecBuildTimes = object
    ship*: int
    army*: int
    marine*: int
    groundBattery*: int
    planetaryShield*: int
    spaceport*: int
    shipyard*: int
    drydock*: int
    starbase*: int

proc findChild(node: KdlNode, name: string): Option[KdlNode] =
  for child in node.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

proc findTop(doc: KdlDoc, name: string): Option[KdlNode] =
  for node in doc:
    if node.name == name:
      return some(node)
  none(KdlNode)

proc childInt(
    node: KdlNode, name: string, defaultValue: int = 0
): int =
  for child in node.children:
    if child.name == name and child.args.len > 0:
      return child.args[0].kInt().int
  defaultValue

proc childFloat(
    node: KdlNode, name: string, defaultValue: float = 0.0
): float =
  for child in node.children:
    if child.name == name and child.args.len > 0:
      return child.args[0].kFloat()
  defaultValue

proc configPath(name: string): string =
  let baseDir = currentSourcePath().splitPath.head
  result = baseDir / ".." / ".." / ".." / "config" / name
  result.normalizePath()

proc loadBuildTimes*(): SpecBuildTimes =
  let doc = parseKdl(staticRead(configPath("construction.kdl")))
  let buildTimesOpt = doc.findTop("buildTimes")
  if buildTimesOpt.isNone:
    return SpecBuildTimes()
  let buildTimes = buildTimesOpt.get()
  SpecBuildTimes(
    ship: buildTimes.childInt("ship", 1),
    army: buildTimes.childInt("army", 1),
    marine: buildTimes.childInt("marine", 1),
    groundBattery: buildTimes.childInt("groundBattery", 1),
    planetaryShield: buildTimes.childInt("planetaryShield", 1),
    spaceport: buildTimes.childInt("spaceport", 1),
    shipyard: buildTimes.childInt("shipyard", 1),
    drydock: buildTimes.childInt("drydock", 1),
    starbase: buildTimes.childInt("starbase", 1)
  )

proc loadShipRow(
    doc: KdlDoc, group: string, name: string
): KdlNode =
  let groupNodeOpt = doc.findTop(group)
  if groupNodeOpt.isNone:
    return KdlNode()
  let groupNode = groupNodeOpt.get()
  let shipOpt = groupNode.findChild(name)
  if shipOpt.isNone:
    return KdlNode()
  shipOpt.get()

proc loadGroundRow(doc: KdlDoc, name: string): KdlNode =
  let groupOpt = doc.findTop("groundUnits")
  if groupOpt.isNone:
    return KdlNode()
  let group = groupOpt.get()
  let unitOpt = group.findChild(name)
  if unitOpt.isNone:
    return KdlNode()
  unitOpt.get()

proc loadFacilityRow(
    doc: KdlDoc, group: string, name: string
): KdlNode =
  let groupOpt = doc.findTop(group)
  if groupOpt.isNone:
    return KdlNode()
  let groupNode = groupOpt.get()
  let facOpt = groupNode.findChild(name)
  if facOpt.isNone:
    return KdlNode()
  facOpt.get()

proc shipRow(
    doc: KdlDoc,
    shipClass: ShipClass,
    code: string,
    displayName: string,
    group: string,
    name: string
): ShipSpecRow =
  let node = doc.loadShipRow(group, name)
  let pc = node.childInt("buildCost", 0)
  let mcPct = int(round(
    node.childFloat("maintenancePercent", 0.0) * 100.0
  ))
  let attack = node.childInt("attackStrength", -1)
  let defense = node.childInt("defenseStrength", -1)
  let command = node.childInt("c2Cost", -1)
  let carry = node.childInt("carryLimit", -1)
  ShipSpecRow(
    shipClass: shipClass,
    code: code,
    name: displayName,
    cst: node.childInt("minCST", 1),
    pc: pc,
    mcPct: mcPct,
    attack: attack,
    defense: defense,
    command: command,
    carry: carry
  )

proc groundRow(
    doc: KdlDoc,
    groundClass: GroundClass,
    code: string,
    displayName: string,
    name: string
): GroundSpecRow =
  let node = doc.loadGroundRow(name)
  let pc = node.childInt("buildCost", 0)
  let mcPct = int(round(
    node.childFloat("maintenancePercent", 0.0) * 100.0
  ))
  GroundSpecRow(
    groundClass: groundClass,
    code: code,
    name: displayName,
    cst: node.childInt("minCST", 1),
    pc: pc,
    mcPct: mcPct,
    attack: node.childInt("attackStrength", 0),
    defense: node.childInt("defenseStrength", 0)
  )

proc facilityRow(
    doc: KdlDoc,
    facilityClass: FacilityClass,
    code: string,
    displayName: string,
    group: string,
    name: string,
    time: int
): FacilitySpecRow =
  let node = doc.loadFacilityRow(group, name)
  let pc = node.childInt("buildCost", 0)
  let mcPct = int(round(
    node.childFloat("maintenancePercent", 0.0) * 100.0
  ))
  FacilitySpecRow(
    facilityClass: facilityClass,
    code: code,
    name: displayName,
    cst: node.childInt("minCST", 1),
    pc: pc,
    mcPct: mcPct,
    attack: node.childInt("attackStrength", -1),
    defense: node.childInt("defenseStrength", 0),
    docks: node.childInt("docks", -1),
    time: time
  )

const
  BuildTimes* = static(loadBuildTimes())

  ShipSpecRows*: array[17, ShipSpecRow] = static:
    let doc = parseKdl(staticRead(configPath("ships.kdl")))
    [
      shipRow(doc, ShipClass.Corvette, "CT", "Corvette",
        "escorts", "corvette"),
      shipRow(doc, ShipClass.Frigate, "FG", "Frigate",
        "escorts", "frigate"),
      shipRow(doc, ShipClass.Destroyer, "DD", "Destroyer",
        "escorts", "destroyer"),
      shipRow(doc, ShipClass.LightCruiser, "CL", "Light Cruiser",
        "escorts", "lightCruiser"),
      shipRow(doc, ShipClass.Cruiser, "CA", "Cruiser",
        "capitals", "cruiser"),
      shipRow(doc, ShipClass.Battlecruiser, "BC", "Battle Cruiser",
        "capitals", "battlecruiser"),
      shipRow(doc, ShipClass.Battleship, "BB", "Battleship",
        "capitals", "battleship"),
      shipRow(doc, ShipClass.Dreadnought, "DN", "Dreadnought",
        "capitals", "dreadnought"),
      shipRow(
        doc, ShipClass.SuperDreadnought, "SD",
        "Super Dreadnought", "capitals", "superDreadnought"
      ),
      shipRow(doc, ShipClass.Carrier, "CV", "Carrier",
        "capitals", "carrier"),
      shipRow(doc, ShipClass.SuperCarrier, "CX", "Super Carrier",
        "capitals", "supercarrier"),
      shipRow(doc, ShipClass.Raider, "RR", "Raider",
        "capitals", "raider"),
      shipRow(doc, ShipClass.Scout, "SC", "Scout",
        "auxiliary", "scout"),
      shipRow(doc, ShipClass.ETAC, "ET", "ETAC",
        "auxiliary", "etac"),
      shipRow(
        doc, ShipClass.TroopTransport, "TT", "Troop Transport",
        "auxiliary", "troopTransport"
      ),
      shipRow(doc, ShipClass.Fighter, "F", "Fighter",
        "fighters", "fighter"),
      shipRow(doc, ShipClass.PlanetBreaker, "PB", "Planet Breaker",
        "specialWeapons", "planetBreaker")
    ]

  GroundSpecRows*: array[4, GroundSpecRow] = static:
    let doc = parseKdl(staticRead(configPath("ground_units.kdl")))
    [
      groundRow(doc, GroundClass.PlanetaryShield, "PS",
        "Planetary Shield", "planetaryShield"),
      groundRow(doc, GroundClass.GroundBattery, "GB",
        "Ground Batteries", "groundBattery"),
      groundRow(doc, GroundClass.Army, "AA", "Armies", "army"),
      groundRow(doc, GroundClass.Marine, "MD", "Space Marines", "marine")
    ]

  FacilitySpecRows*: array[4, FacilitySpecRow] = static:
    let doc = parseKdl(staticRead(configPath("facilities.kdl")))
    [
      facilityRow(
        doc, FacilityClass.Spaceport, "SP", "Spaceport",
        "facilities", "spaceport", BuildTimes.spaceport
      ),
      facilityRow(
        doc, FacilityClass.Shipyard, "SY", "Shipyard",
        "facilities", "shipyard", BuildTimes.shipyard
      ),
      facilityRow(
        doc, FacilityClass.Drydock, "DD", "Drydock",
        "facilities", "drydock", BuildTimes.drydock
      ),
      facilityRow(
        doc, FacilityClass.Starbase, "SB", "Starbase",
        "orbitalDefenses", "starbase", BuildTimes.starbase
      )
    ]

proc buildRowCount*(category: BuildCategory): int =
  case category
  of BuildCategory.Ships:
    ShipSpecRows.len
  of BuildCategory.Ground:
    GroundSpecRows.len
  of BuildCategory.Facilities:
    FacilitySpecRows.len

proc buildRowKey*(category: BuildCategory, idx: int): BuildRowKey =
  case category
  of BuildCategory.Ships:
    let row = ShipSpecRows[idx]
    BuildRowKey(
      kind: BuildOptionKind.Ship,
      shipClass: some(row.shipClass),
      groundClass: none(GroundClass),
      facilityClass: none(FacilityClass)
    )
  of BuildCategory.Ground:
    let row = GroundSpecRows[idx]
    BuildRowKey(
      kind: BuildOptionKind.Ground,
      shipClass: none(ShipClass),
      groundClass: some(row.groundClass),
      facilityClass: none(FacilityClass)
    )
  of BuildCategory.Facilities:
    let row = FacilitySpecRows[idx]
    BuildRowKey(
      kind: BuildOptionKind.Facility,
      shipClass: none(ShipClass),
      groundClass: none(GroundClass),
      facilityClass: some(row.facilityClass)
    )
