## Shared authoritative rules payload for engine <-> player sync.

import std/[options, strutils]
import msgpack4nim
import nimcrypto/sha2
import ../engine/types/config

const
  ConfigSchemaVersion* = 1'i32
  TechSectionVersion* = 1'i32
  ShipsSectionVersion* = 1'i32
  GroundUnitsSectionVersion* = 1'i32
  FacilitiesSectionVersion* = 1'i32
  ConstructionSectionVersion* = 1'i32
  LimitsSectionVersion* = 1'i32
  EconomySectionVersion* = 1'i32

type
  TuiRulesSections* = object
    tech*: Option[TechConfig]
    ships*: Option[ShipsConfig]
    groundUnits*: Option[GroundUnitsConfig]
    facilities*: Option[FacilitiesConfig]
    construction*: Option[ConstructionConfig]
    limits*: Option[LimitsConfig]
    economy*: Option[EconomyConfig]

  TuiRulesSnapshot* = object
    schemaVersion*: int32
    configHash*: string
    capabilities*: seq[string]
    techVersion*: int32
    shipsVersion*: int32
    groundUnitsVersion*: int32
    facilitiesVersion*: int32
    constructionVersion*: int32
    limitsVersion*: int32
    economyVersion*: int32
    sections*: TuiRulesSections

  ## Backward-compatible alias while transitioning call sites.
  AuthoritativeConfig* = TuiRulesSnapshot

proc sha256Hex(data: string): string =
  let digest = sha256.digest(data)
  var hexValue = newStringOfCap(64)
  for value in digest.data:
    hexValue.add(value.toHex(2).toLowerAscii())
  hexValue

proc requiredCapabilities*(): seq[string] =
  @[
    "rd.v1",
    "build.v1",
    "limits.v1",
    "economy.v1"
  ]

proc computeConfigHash*(snapshot: TuiRulesSnapshot): string =
  ## Stable hash for rules integrity checks across daemon and player.
  var normalized = snapshot
  normalized.configHash = ""
  let packed = pack(normalized)
  sha256Hex(packed)

proc buildTuiRulesSnapshot*(config: GameConfig): TuiRulesSnapshot =
  result = TuiRulesSnapshot(
    schemaVersion: ConfigSchemaVersion,
    capabilities: requiredCapabilities(),
    techVersion: TechSectionVersion,
    shipsVersion: ShipsSectionVersion,
    groundUnitsVersion: GroundUnitsSectionVersion,
    facilitiesVersion: FacilitiesSectionVersion,
    constructionVersion: ConstructionSectionVersion,
    limitsVersion: LimitsSectionVersion,
    economyVersion: EconomySectionVersion,
    sections: TuiRulesSections(
      tech: some(config.tech),
      ships: some(config.ships),
      groundUnits: some(config.groundUnits),
      facilities: some(config.facilities),
      construction: some(config.construction),
      limits: some(config.limits),
      economy: some(config.economy)
    )
  )
  result.configHash = computeConfigHash(result)

proc hasRequiredSections*(snapshot: TuiRulesSnapshot): bool =
  snapshot.sections.tech.isSome and
    snapshot.sections.ships.isSome and
    snapshot.sections.groundUnits.isSome and
    snapshot.sections.facilities.isSome and
    snapshot.sections.construction.isSome and
    snapshot.sections.limits.isSome and
    snapshot.sections.economy.isSome

proc hasRequiredCapabilities*(snapshot: TuiRulesSnapshot): bool =
  let capabilities = requiredCapabilities()
  for cap in capabilities:
    if cap notin snapshot.capabilities:
      return false
  true

proc toGameConfig*(snapshot: TuiRulesSnapshot): Option[GameConfig] =
  ## Materialize minimal GameConfig needed by current player TUI.
  if not snapshot.hasRequiredSections():
    return none(GameConfig)
  if not snapshot.hasRequiredCapabilities():
    return none(GameConfig)

  var config = GameConfig()
  config.tech = snapshot.sections.tech.get()
  config.ships = snapshot.sections.ships.get()
  config.groundUnits = snapshot.sections.groundUnits.get()
  config.facilities = snapshot.sections.facilities.get()
  config.construction = snapshot.sections.construction.get()
  config.limits = snapshot.sections.limits.get()
  config.economy = snapshot.sections.economy.get()
  some(config)
