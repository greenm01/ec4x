## Research tech display helpers for TUI

import std/[math, strutils, tables]

import ../../../engine/globals
import ../../../engine/systems/tech/costs
import ../../../engine/types/tech
import ../../sam/tui_model

proc maxKey[T](levels: Table[int32, T]): int =
  result = 1
  for key in levels.keys:
    let level = key.int
    if level > result:
      result = level

proc maxFromValues(values: openArray[int]): int =
  result = 1
  for value in values:
    if value > result:
      result = value

proc progressionMaxLevel*(item: ResearchItem): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    maxKey(gameConfig.tech.el.levels)
  of ResearchItemKind.ScienceLevel:
    maxKey(gameConfig.tech.sl.levels)
  of ResearchItemKind.Technology:
    case item.field
    of TechField.WeaponsTech:
      maxKey(gameConfig.tech.wep.levels)
    of TechField.ConstructionTech:
      maxKey(gameConfig.tech.cst.levels)
    of TechField.TerraformingTech:
      maxKey(gameConfig.tech.ter.levels)
    of TechField.ElectronicIntelligence:
      maxKey(gameConfig.tech.eli.levels)
    of TechField.CloakingTech:
      maxKey(gameConfig.tech.clk.levels)
    of TechField.ShieldTech:
      maxKey(gameConfig.tech.sld.levels)
    of TechField.CounterIntelligence:
      maxKey(gameConfig.tech.cic.levels)
    of TechField.StrategicLiftTech:
      maxKey(gameConfig.tech.stl.levels)
    of TechField.FlagshipCommandTech:
      maxKey(gameConfig.tech.fc.levels)
    of TechField.StrategicCommandTech:
      maxKey(gameConfig.tech.sc.levels)
    of TechField.FighterDoctrine:
      maxKey(gameConfig.tech.fd.levels)
    of TechField.AdvancedCarrierOps:
      maxKey(gameConfig.tech.aco.levels)

proc maxProgressionLevel*(): int =
  maxFromValues([
    maxKey(gameConfig.tech.el.levels),
    maxKey(gameConfig.tech.sl.levels),
    maxKey(gameConfig.tech.wep.levels),
    maxKey(gameConfig.tech.cst.levels),
    maxKey(gameConfig.tech.ter.levels),
    maxKey(gameConfig.tech.eli.levels),
    maxKey(gameConfig.tech.clk.levels),
    maxKey(gameConfig.tech.sld.levels),
    maxKey(gameConfig.tech.cic.levels),
    maxKey(gameConfig.tech.stl.levels),
    maxKey(gameConfig.tech.fc.levels),
    maxKey(gameConfig.tech.sc.levels),
    maxKey(gameConfig.tech.fd.levels),
    maxKey(gameConfig.tech.aco.levels)
  ])

proc techDescription*(item: ResearchItem): string =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    "Improves industrial output and economic efficiency."
  of ResearchItemKind.ScienceLevel:
    "Gates access to advanced research tiers."
  of ResearchItemKind.Technology:
    case item.field
    of TechField.WeaponsTech:
      "Improves ship AS/DS; baked into new hulls."
    of TechField.ConstructionTech:
      "Unlocks hulls and increases dock capacity."
    of TechField.TerraformingTech:
      "Unlocks planet class upgrades."
    of TechField.ElectronicIntelligence:
      "Improves detection against stealth and espionage."
    of TechField.CloakingTech:
      "Improves raider stealth and ambush odds."
    of TechField.ShieldTech:
      "Enables planetary shields against bombardment."
    of TechField.CounterIntelligence:
      "Improves defense against hostile espionage."
    of TechField.StrategicLiftTech:
      "Increases troop transport capacity."
    of TechField.FlagshipCommandTech:
      "Increases maximum ships per fleet."
    of TechField.StrategicCommandTech:
      "Increases total combat fleets and C2."
    of TechField.FighterDoctrine:
      "Boosts colony fighter capacity."
    of TechField.AdvancedCarrierOps:
      "Improves carrier fighter capacity."

proc formatMultiplier(value: float32): string =
  let raw = formatFloat(value, ffDecimal, 1)
  if raw.endsWith(".0"):
    result = raw[0 .. ^3]
  else:
    result = raw

proc wepPercent(level: int): int =
  if level <= 1:
    return 0
  let base = float(gameConfig.tech.wep.weaponsStatIncreasePerLevel)
  let mult = pow(base, float(level - 1))
  int(round((mult - 1.0) * 100.0))

proc techEffectForLevel*(item: ResearchItem, level: int): string =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    if level <= 1:
      "Base output"
    elif gameConfig.tech.el.levels.hasKey(int32(level)):
      let mult = gameConfig.tech.el.levels[int32(level)].multiplier
      "IU x" & formatMultiplier(mult)
    else:
      "IU x" & formatMultiplier(elModifier(int32(level)))
  of ResearchItemKind.ScienceLevel:
    if level <= 1:
      "Base infrastructure"
    elif gameConfig.tech.sl.levels.hasKey(int32(level)):
      let data = gameConfig.tech.sl.levels[int32(level)]
      "ERP " & $data.erpRequired & " SRP " & $data.srpRequired
    else:
      "Research tier " & $level
  of ResearchItemKind.Technology:
    case item.field
    of TechField.WeaponsTech:
      if level <= 1:
        "Base AS/DS"
      else:
        "AS/DS +" & $wepPercent(level) & "%"
    of TechField.ConstructionTech:
      let base = gameConfig.tech.cst.baseModifier
      let inc = gameConfig.tech.cst.incrementPerLevel
      let mult = float32(base) + float32(level - 1) * float32(inc)
      if gameConfig.tech.cst.levels.hasKey(int32(level)):
        let unlocks = gameConfig.tech.cst.levels[int32(level)].unlocks
        if unlocks.len > 0:
          "Docks x" & formatMultiplier(mult) & "; Unlocks " &
            unlocks.join(",")
        else:
          "Docks x" & formatMultiplier(mult)
      else:
        "Docks x" & formatMultiplier(mult)
    of TechField.TerraformingTech:
      if gameConfig.tech.ter.levels.hasKey(int32(level)):
        let data = gameConfig.tech.ter.levels[int32(level)]
        "Upgrade to " & data.planetClass & " (" & $data.ppCost & " PP)"
      else:
        "Terraforming tier " & $level
    of TechField.ElectronicIntelligence:
      "Detection tier " & $level
    of TechField.CloakingTech:
      "Cloak tier " & $level
    of TechField.ShieldTech:
      if gameConfig.tech.sld.levels.hasKey(int32(level)):
        let data = gameConfig.tech.sld.levels[int32(level)]
        "Absorb " & $data.absorption & "% / DS +" & $data.shieldDs
      else:
        "Shield tier " & $level
    of TechField.CounterIntelligence:
      "Counter tier " & $level
    of TechField.StrategicLiftTech:
      "Lift tier " & $level
    of TechField.FlagshipCommandTech:
      if gameConfig.tech.fc.levels.hasKey(int32(level)):
        let data = gameConfig.tech.fc.levels[int32(level)]
        "Fleet size " & $data.maxShipsPerFleet
      else:
        "Fleet size tier " & $level
    of TechField.StrategicCommandTech:
      if gameConfig.tech.sc.levels.hasKey(int32(level)):
        let data = gameConfig.tech.sc.levels[int32(level)]
        "C2 +" & $data.c2Bonus & ", Fleets " & $data.maxCombatFleetsBase
      else:
        "Command tier " & $level
    of TechField.FighterDoctrine:
      if gameConfig.tech.fd.levels.hasKey(int32(level)):
        let data = gameConfig.tech.fd.levels[int32(level)]
        "Fighter cap x" & formatMultiplier(data.capacityMultiplier)
      else:
        "Fighter tier " & $level
    of TechField.AdvancedCarrierOps:
      if gameConfig.tech.aco.levels.hasKey(int32(level)):
        let data = gameConfig.tech.aco.levels[int32(level)]
        "CV " & $data.cvCapacity & " / CX " & $data.cxCapacity
      else:
        "Carrier tier " & $level

proc techCostForLevel*(item: ResearchItem, level: int): int =
  if level <= 1:
    return 0
  if item.kind == ResearchItemKind.EconomicLevel:
    return elUpgradeCost(int32(level - 1)).int
  if item.kind == ResearchItemKind.ScienceLevel:
    return slUpgradeCost(int32(level - 1)).int
  techUpgradeCost(item.field, int32(level - 1)).int

proc techSlRequiredForLevel*(item: ResearchItem, level: int): int =
  if item.kind == ResearchItemKind.ScienceLevel:
    return 0
  if level <= 0:
    return 0
  let lvl = int32(level)
  if item.kind == ResearchItemKind.EconomicLevel:
    if gameConfig.tech.el.levels.hasKey(lvl):
      return gameConfig.tech.el.levels[lvl].slRequired.int
    return 0
  case item.field
  of TechField.ConstructionTech:
    if gameConfig.tech.cst.levels.hasKey(lvl):
      return gameConfig.tech.cst.levels[lvl].slRequired.int
  of TechField.WeaponsTech:
    if gameConfig.tech.wep.levels.hasKey(lvl):
      return gameConfig.tech.wep.levels[lvl].slRequired.int
  of TechField.TerraformingTech:
    if gameConfig.tech.ter.levels.hasKey(lvl):
      return gameConfig.tech.ter.levels[lvl].slRequired.int
  of TechField.ElectronicIntelligence:
    if gameConfig.tech.eli.levels.hasKey(lvl):
      return gameConfig.tech.eli.levels[lvl].slRequired.int
  of TechField.CloakingTech:
    if gameConfig.tech.clk.levels.hasKey(lvl):
      return gameConfig.tech.clk.levels[lvl].slRequired.int
  of TechField.ShieldTech:
    if gameConfig.tech.sld.levels.hasKey(lvl):
      return gameConfig.tech.sld.levels[lvl].slRequired.int
  of TechField.CounterIntelligence:
    if gameConfig.tech.cic.levels.hasKey(lvl):
      return gameConfig.tech.cic.levels[lvl].slRequired.int
  of TechField.StrategicLiftTech:
    if gameConfig.tech.stl.levels.hasKey(lvl):
      return gameConfig.tech.stl.levels[lvl].slRequired.int
  of TechField.FlagshipCommandTech:
    if gameConfig.tech.fc.levels.hasKey(lvl):
      return gameConfig.tech.fc.levels[lvl].slRequired.int
  of TechField.StrategicCommandTech:
    if gameConfig.tech.sc.levels.hasKey(lvl):
      return gameConfig.tech.sc.levels[lvl].slRequired.int
  of TechField.FighterDoctrine:
    if gameConfig.tech.fd.levels.hasKey(lvl):
      return gameConfig.tech.fd.levels[lvl].slRequired.int
  of TechField.AdvancedCarrierOps:
    if gameConfig.tech.aco.levels.hasKey(lvl):
      return gameConfig.tech.aco.levels[lvl].slRequired.int
  return 0
