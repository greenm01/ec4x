## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.kdl
## Allows runtime configuration for all tech trees

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseEconomicLevel(node: KdlNode, ctx: var KdlConfigContext): ElConfig =
  ## Parse economicLevel with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## economicLevel {
  ##   level 2 { slRequired 2; erpCost 10; multiplier 1.5 }
  ##   level 3 { slRequired 3; erpCost 15; multiplier 2.0 }
  ## }
  ## ```
  result = ElConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (2-10)
      if levelNum >= 2 and levelNum <= 10:
        result.levels[levelNum] = ElLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          erpCost: child.requireInt32("erpCost", ctx),
          multiplier: child.requireFloat32("multiplier", ctx)
        )

proc parseScienceLevel(node: KdlNode, ctx: var KdlConfigContext): SlConfig =
  ## Parse scienceLevel with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## scienceLevel {
  ##   level 2 { erpRequired 10; srpRequired 10 }
  ##   level 3 { erpRequired 12; srpRequired 13 }
  ## }
  ## ```
  ##
  ## Note: SL advancement uses srpRequired.
  ## erpRequired is retained for compatibility and display tables.
  result = SlConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (2-10)
      if levelNum >= 2 and levelNum <= 10:
        result.levels[levelNum] = SlLevelData(
          erpRequired: child.requireInt32("erpRequired", ctx),
          srpRequired: child.requireInt32("srpRequired", ctx)
        )

proc parseElectronicIntelligence(
  node: KdlNode,
  ctx: var KdlConfigContext
): EliConfig =
  ## Parse electronicIntelligence with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## electronicIntelligence {
  ##   capacityMultiplierPerLevel 0.10
  ##   level 1 { slRequired 1; trpCost 10 }
  ## }
  ## ```
  result = EliConfig()

  # Parse capacityMultiplierPerLevel if present
  try:
    result.capacityMultiplierPerLevel =
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  except ConfigError:
    result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-15)
      if levelNum >= 1 and levelNum <= 15:
        result.levels[levelNum] = EliLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx)
        )

proc parseCloaking(
  node: KdlNode,
  ctx: var KdlConfigContext
): ClkConfig =
  ## Parse cloaking with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## cloaking {
  ##   capacityMultiplierPerLevel 0.10
  ##   level 1 { slRequired 1; trpCost 10 }
  ## }
  ## ```
  result = ClkConfig()

  # Parse capacityMultiplierPerLevel if present
  try:
    result.capacityMultiplierPerLevel =
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  except ConfigError:
    result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-15)
      if levelNum >= 1 and levelNum <= 15:
        result.levels[levelNum] = ClkLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx)
        )

proc parseCounterIntelligence(
  node: KdlNode,
  ctx: var KdlConfigContext
): CicConfig =
  ## Parse counterIntelligence with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## counterIntelligence {
  ##   capacityMultiplierPerLevel 0.10
  ##   level 1 { slRequired 1; trpCost 10 }
  ## }
  ## ```
  result = CicConfig()

  # Parse capacityMultiplierPerLevel if present
  try:
    result.capacityMultiplierPerLevel =
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  except ConfigError:
    result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-15)
      if levelNum >= 1 and levelNum <= 15:
        result.levels[levelNum] = CicLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx)
        )

proc parseStrategicLift(
  node: KdlNode,
  ctx: var KdlConfigContext
): StlConfig =
  ## Parse strategicLift with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## strategicLift {
  ##   capacityMultiplierPerLevel 0.10
  ##   level 1 { slRequired 1; trpCost 10 }
  ## }
  ## ```
  result = StlConfig()

  # Parse capacityMultiplierPerLevel if present
  try:
    result.capacityMultiplierPerLevel =
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  except ConfigError:
    result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-15)
      if levelNum >= 1 and levelNum <= 15:
        result.levels[levelNum] = StlLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx)
        )

proc parseWeaponsTech(node: KdlNode, ctx: var KdlConfigContext): WepConfig =
  ## Parse weaponsTech with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## weapons {
  ##   baseMultiplier 1.10
  ##   level 2 { slRequired 2; trpCost 10 }
  ## }
  ## ```
  result = WepConfig()

  # Parse base-level fields
  result.weaponsStatIncreasePerLevel =
    node.requireFloat32("baseMultiplier", ctx)
  result.weaponsCostIncreasePerLevel = 0.0  # Not in current KDL

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (2-10)
      if levelNum >= 2 and levelNum <= 10:
        result.levels[levelNum] = WepLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx)
        )

proc parseConstructionTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): CstConfig =
  ## Parse construction tech with special fields
  ##
  ## Expected structure:
  ## ```kdl
  ## construction {
  ##   baseModifier 1.0
  ##   incrementPerLevel 0.10
  ##   capacityMultiplierPerLevel 0.10
  ##   level 2 { slRequired 2; trpCost 10; unlocks "BC" }
  ## }
  ## ```
  result = CstConfig(
    baseModifier: node.requireFloat32("baseModifier", ctx),
    incrementPerLevel: node.requireFloat32("incrementPerLevel", ctx)
  )

  # Try to get capacityMultiplierPerLevel if it exists
  try:
    result.capacityMultiplierPerLevel =
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  except ConfigError:
    result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (2-10)
      if levelNum >= 2 and levelNum <= 10:
        # Parse unlocks property (can have multiple values)
        var unlocks: seq[string] = @[]
        try:
          let unlocksNode = child.property("unlocks")
          if unlocksNode.isSome:
            let val = unlocksNode.get()
            if val.kind == KValKind.KString:
              unlocks.add(val.kString())
          # If there are multiple unlocks as separate properties,
          # they'll be space-separated in KDL, handled by kdl parser
          for arg in child.args:
            if arg.kind == KValKind.KString:
              let val = arg.kString()
              if val.len == 2 or val.len == 3:  # Ship codes like "BC", "BB"
                unlocks.add(val)
        except: discard

        result.levels[levelNum] = CstLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx),
          unlocks: unlocks
        )

proc parseShieldTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): SldConfig =
  ## Parse shield tech with special fields
  ##
  ## Expected structure:
  ## ```kdl
  ## shields {
  ##   level 1 {
  ##     slRequired 2; srpCost 10
  ##     absorption 15; shieldDs 10
  ##     d20Threshold 17; hitsBlocked 0.25
  ##   }
  ## }
  ## ```
  result = SldConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-6)
      if levelNum >= 1 and levelNum <= 6:
        result.levels[levelNum] = SldLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx),
          absorption: child.requireInt32("absorption", ctx),
          shieldDs: child.requireInt32("shieldDs", ctx),
          d20Threshold: child.requireInt32("d20Threshold", ctx),
          hitsBlocked: child.requireFloat32("hitsBlocked", ctx)
        )

proc parseTerraformingTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerConfig =
  ## Parse terraformingTech with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## terraforming {
  ##   level 1 {
  ##     slRequired 4; srpCost 16; ppCost 100
  ##     upgrades "Extreme" to "Desolate"
  ##   }
  ## }
  ## ```
  result = TerConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Get target planet class from "upgrades" child
      # Format: upgrades "Extreme" to "Desolate"
      var planetClass = ""
      for upgradeChild in child.children:
        if upgradeChild.name == "upgrades" and upgradeChild.args.len >= 3:
          # args[2] is the target class (after "to")
          planetClass = upgradeChild.args[2].kString()
          break

      # Store with actual level number as key (1-6)
      if levelNum >= 1 and levelNum <= 6:
        result.levels[levelNum] = TerLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          srpCost: child.requireInt32("srpCost", ctx),
          ppCost: child.requireInt32("ppCost", ctx),
          planetClass: planetClass
        )

proc parseTerraformingUpgradeCosts(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerCostsConfig =
  ## Parse terraformingUpgradeCosts with flat planet type fields
  ##
  ## Expected structure:
  ## ```kdl
  ## terraformingUpgradeCosts {
  ##   extremeTer 1; extremePuMin 1; extremePuMax 20; extremePp 15
  ##   desolateTer 1; desolatePuMin 21; desolatePuMax 60; desolatePp 12
  ## }
  ## ```
  result = TerCostsConfig()

  # Parse each planet type's costs
  result.costs[PlanetClass.Extreme] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("extremeTer", ctx),
    puMin: node.requireInt32("extremePuMin", ctx),
    puMax: node.requireInt32("extremePuMax", ctx),
    ppCost: node.requireInt32("extremePp", ctx)
  )

  result.costs[PlanetClass.Desolate] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("desolateTer", ctx),
    puMin: node.requireInt32("desolatePuMin", ctx),
    puMax: node.requireInt32("desolatePuMax", ctx),
    ppCost: node.requireInt32("desolatePp", ctx)
  )

  result.costs[PlanetClass.Hostile] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("hostileTer", ctx),
    puMin: node.requireInt32("hostilePuMin", ctx),
    puMax: node.requireInt32("hostilePuMax", ctx),
    ppCost: node.requireInt32("hostilePp", ctx)
  )

  result.costs[PlanetClass.Harsh] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("harshTer", ctx),
    puMin: node.requireInt32("harshPuMin", ctx),
    puMax: node.requireInt32("harshPuMax", ctx),
    ppCost: node.requireInt32("harshPp", ctx)
  )

  result.costs[PlanetClass.Benign] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("benignTer", ctx),
    puMin: node.requireInt32("benignPuMin", ctx),
    puMax: node.requireInt32("benignPuMax", ctx),
    ppCost: node.requireInt32("benignPp", ctx)
  )

  result.costs[PlanetClass.Lush] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("lushTer", ctx),
    puMin: node.requireInt32("lushPuMin", ctx),
    puMax: node.requireInt32("lushPuMax", ctx),
    ppCost: node.requireInt32("lushPp", ctx)
  )

  result.costs[PlanetClass.Eden] = TerraformingUpgradeCostData(
    terRequired: node.requireInt32("edenTer", ctx),
    puMin: node.requireInt32("edenPuMin", ctx),
    puMax: node.requireInt32("edenPuMax", ctx),
    ppCost: node.requireInt32("edenPp", ctx)
  )

proc parseFleetCommand(
  node: KdlNode,
  ctx: var KdlConfigContext
): FcConfig =
  ## Parse fleetCommand with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## fleetCommand {
  ##   level 1 { slRequired 1; trpCost 0; maxShipsPerFleet 10 }
  ## }
  ## ```
  result = FcConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-6)
      if levelNum >= 1 and levelNum <= 6:
        result.levels[levelNum] = FcLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx),
          maxShipsPerFleet: child.requireInt32("maxShipsPerFleet", ctx)
        )

proc parseStrategicCommand(
  node: KdlNode,
  ctx: var KdlConfigContext
): ScConfig =
  ## Parse strategicCommand with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## strategicCommand {
  ##   level 1 { slRequired 1; trpCost 0; c2Bonus 50; maxCombatFleetsBase 10 }
  ## }
  ## ```
  result = ScConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Store with actual level number as key (1-6)
      if levelNum >= 1 and levelNum <= 6:
        result.levels[levelNum] = ScLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx),
          c2Bonus: child.requireInt32("c2Bonus", ctx),
          maxCombatFleetsBase: child.requireInt32("maxCombatFleetsBase", ctx)
        )

proc parseFighterDoctrine(
  node: KdlNode,
  ctx: var KdlConfigContext
): FdConfig =
  ## Parse fighterDoctrine with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## fighterDoctrine {
  ##   level 2 {
  ##     slRequired 2
  ##     trpCost 15
  ##     multiplier 1.5
  ##   }
  ## }
  ## ```
  result = FdConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Optional description field
      var description = ""
      try:
        description = child.requireString("description", ctx)
      except ConfigError:
        description = ""

      # Store with actual level number as key (2-3)
      if levelNum >= 2 and levelNum <= 3:
        result.levels[levelNum] = FdLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx),
          capacityMultiplier: child.requireFloat32("multiplier", ctx),
          description: description
        )

proc parseAdvancedCarrierOps(
  node: KdlNode,
  ctx: var KdlConfigContext
): AcoConfig =
  ## Parse advancedCarrierOperations with hierarchical level nodes
  ##
  ## Expected structure:
  ## ```kdl
  ## advancedCarrierOperations {
  ##   capacityMultiplierPerLevel 0.15
  ##   level 1 {
  ##     slRequired 1
  ##     trpCost 0
  ##     cvCapacity 3
  ##     cxCapacity 5
  ##     description "Basic ops"
  ##   }
  ## }
  ## ```
  result = AcoConfig(
    capacityMultiplierPerLevel:
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  )

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].kInt().int32

      # Optional description field
      var description = ""
      try:
        description = child.requireString("description", ctx)
      except ConfigError:
        description = ""

      # Store with actual level number as key (1-3)
      if levelNum >= 1 and levelNum <= 3:
        result.levels[levelNum] = AcoLevelData(
          slRequired: child.requireInt32("slRequired", ctx),
          trpCost: child.requireInt32("trpCost", ctx),
          cvCapacity: child.requireInt32("cvCapacity", ctx),
          cxCapacity: child.requireInt32("cxCapacity", ctx),
          description: description
        )

proc loadTechConfig*(configPath: string): TechConfig =
  ## Load technology configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("economicLevel"):
    let node = doc.requireNode("economicLevel", ctx)
    result.el = parseEconomicLevel(node, ctx)

  ctx.withNode("scienceLevel"):
    let node = doc.requireNode("scienceLevel", ctx)
    result.sl = parseScienceLevel(node, ctx)

  ctx.withNode("construction"):
    let node = doc.requireNode("construction", ctx)
    result.cst = parseConstructionTech(node, ctx)

  ctx.withNode("weapons"):
    let node = doc.requireNode("weapons", ctx)
    result.wep = parseWeaponsTech(node, ctx)

  ctx.withNode("terraforming"):
    let node = doc.requireNode("terraforming", ctx)
    result.ter = parseTerraformingTech(node, ctx)

  ctx.withNode("terraformingUpgradeCosts"):
    let node = doc.requireNode("terraformingUpgradeCosts", ctx)
    result.terCosts = parseTerraformingUpgradeCosts(node, ctx)

  ctx.withNode("electronicIntelligence"):
    let node = doc.requireNode("electronicIntelligence", ctx)
    result.eli = parseElectronicIntelligence(node, ctx)

  ctx.withNode("cloaking"):
    let node = doc.requireNode("cloaking", ctx)
    result.clk = parseCloaking(node, ctx)

  ctx.withNode("shields"):
    let node = doc.requireNode("shields", ctx)
    result.sld = parseShieldTech(node, ctx)

  ctx.withNode("counterIntelligence"):
    let node = doc.requireNode("counterIntelligence", ctx)
    result.cic = parseCounterIntelligence(node, ctx)

  ctx.withNode("strategicLift"):
    let node = doc.requireNode("strategicLift", ctx)
    result.stl = parseStrategicLift(node, ctx)

  ctx.withNode("fleetCommand"):
    let node = doc.requireNode("fleetCommand", ctx)
    result.fc = parseFleetCommand(node, ctx)

  ctx.withNode("strategicCommand"):
    let node = doc.requireNode("strategicCommand", ctx)
    result.sc = parseStrategicCommand(node, ctx)

  ctx.withNode("fighterDoctrine"):
    let node = doc.requireNode("fighterDoctrine", ctx)
    result.fd = parseFighterDoctrine(node, ctx)

  ctx.withNode("advancedCarrierOperations"):
    let node = doc.requireNode("advancedCarrierOperations", ctx)
    result.aco = parseAdvancedCarrierOps(node, ctx)

  logInfo("Config", "Loaded technology configuration", "path=", configPath)
