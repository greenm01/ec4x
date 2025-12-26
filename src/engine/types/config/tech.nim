type
  StartingTechConfig* = object
    economicLevel*: int32
    scienceLevel*: int32
    constructionTech*: int32
    weaponsTech*: int32
    terraformingTech*: int32
    electronicIntelligence*: int32
    cloakingTech*: int32
    shieldTech*: int32
    counterIntelligence*: int32
    fighterDoctrine*: int32
    advancedCarrierOps*: int32

  EconomicLevelConfig* = object
    level1Erp*: int32
    level1Mod*: float32
    level2Erp*: int32
    level2Mod*: float32
    level3Erp*: int32
    level3Mod*: float32
    level4Erp*: int32
    level4Mod*: float32
    level5Erp*: int32
    level5Mod*: float32
    level6Erp*: int32
    level6Mod*: float32
    level7Erp*: int32
    level7Mod*: float32
    level8Erp*: int32
    level8Mod*: float32
    level9Erp*: int32
    level9Mod*: float32
    level10Erp*: int32
    level10Mod*: float32
    level11Erp*: int32
    level11Mod*: float32

  ScienceLevelConfig* = object
    level1Srp*: int32
    level2Srp*: int32
    level3Srp*: int32
    level4Srp*: int32
    level5Srp*: int32
    level6Srp*: int32
    level7Srp*: int32
    level8Srp*: int32

  StandardTechLevelConfig* = object
    capacityMultiplierPerLevel*: float32
    level1Sl*: int32
    level1Trp*: int32
    level2Sl*: int32
    level2Trp*: int32
    level3Sl*: int32
    level3Trp*: int32
    level4Sl*: int32
    level4Trp*: int32
    level5Sl*: int32
    level5Trp*: int32
    level6Sl*: int32
    level6Trp*: int32
    level7Sl*: int32
    level7Trp*: int32
    level8Sl*: int32
    level8Trp*: int32
    level9Sl*: int32
    level9Trp*: int32
    level10Sl*: int32
    level10Trp*: int32
    level11Sl*: int32
    level11Trp*: int32
    level12Sl*: int32
    level12Trp*: int32
    level13Sl*: int32
    level13Trp*: int32
    level14Sl*: int32
    level14Trp*: int32
    level15Sl*: int32
    level15Trp*: int32

  WeaponsTechConfig* = object
    weaponsStatIncreasePerLevel*: float32
    weaponsCostIncreasePerLevel*: float32
    level1Sl*: int32
    level1Trp*: int32
    level2Sl*: int32
    level2Trp*: int32
    level3Sl*: int32
    level3Trp*: int32
    level4Sl*: int32
    level4Trp*: int32
    level5Sl*: int32
    level5Trp*: int32
    level6Sl*: int32
    level6Trp*: int32
    level7Sl*: int32
    level7Trp*: int32
    level8Sl*: int32
    level8Trp*: int32
    level9Sl*: int32
    level9Trp*: int32
    level10Sl*: int32
    level10Trp*: int32
    level11Sl*: int32
    level11Trp*: int32
    level12Sl*: int32
    level12Trp*: int32
    level13Sl*: int32
    level13Trp*: int32
    level14Sl*: int32
    level14Trp*: int32
    level15Sl*: int32
    level15Trp*: int32

  TerraformingTechConfig* = object
    level1Sl*: int32
    level1Trp*: int32
    level1PlanetClass*: string
    level2Sl*: int32
    level2Trp*: int32
    level2PlanetClass*: string
    level3Sl*: int32
    level3Trp*: int32
    level3PlanetClass*: string
    level4Sl*: int32
    level4Trp*: int32
    level4PlanetClass*: string
    level5Sl*: int32
    level5Trp*: int32
    level5PlanetClass*: string
    level6Sl*: int32
    level6Trp*: int32
    level6PlanetClass*: string
    level7Sl*: int32
    level7Trp*: int32
    level7PlanetClass*: string

  FighterDoctrineConfig* = object
    level1Sl*: int32
    level1Trp*: int32
    level1CapacityMultiplier*: float32
    level1Description*: string
    level2Sl*: int32
    level2Trp*: int32
    level2CapacityMultiplier*: float32
    level2Description*: string
    level3Sl*: int32
    level3Trp*: int32
    level3CapacityMultiplier*: float32
    level3Description*: string

  AdvancedCarrierOpsConfig* = object
    capacityMultiplierPerLevel*: float32
    level1Sl*: int32
    level1Trp*: int32
    level1CvCapacity*: int32
    level1CxCapacity*: int32
    level1Description*: string
    level2Sl*: int32
    level2Trp*: int32
    level2CvCapacity*: int32
    level2CxCapacity*: int32
    level2Description*: string
    level3Sl*: int32
    level3Trp*: int32
    level3CvCapacity*: int32
    level3CxCapacity*: int32
    level3Description*: string

  TerraformingUpgradeCostsConfig* = object
    extremeTer*: int32
    extremePuMin*: int32
    extremePuMax*: int32
    extremePp*: int32
    desolateTer*: int32
    desolatePuMin*: int32
    desolatePuMax*: int32
    desolatePp*: int32
    hostileTer*: int32
    hostilePuMin*: int32
    hostilePuMax*: int32
    hostilePp*: int32
    harshTer*: int32
    harshPuMin*: int32
    harshPuMax*: int32
    harshPp*: int32
    benignTer*: int32
    benignPuMin*: int32
    benignPuMax*: int32
    benignPp*: int32
    lushTer*: int32
    lushPuMin*: int32
    lushPuMax*: int32
    lushPp*: int32
    edenTer*: int32
    edenPuMin*: int32
    edenPuMax*: int32
    edenPp*: int32

  TechConfig* = object ## Complete technology configuration loaded from KDL
    startingTech*: StartingTechConfig
    economicLevel*: EconomicLevelConfig
    scienceLevel*: ScienceLevelConfig
    constructionTech*: StandardTechLevelConfig
    weaponsTech*: WeaponsTechConfig
    terraformingTech*: TerraformingTechConfig
    terraformingUpgradeCosts*: TerraformingUpgradeCostsConfig
    electronicIntelligence*: StandardTechLevelConfig
    cloakingTech*: StandardTechLevelConfig
    shieldTech*: StandardTechLevelConfig
    counterIntelligenceTech*: StandardTechLevelConfig
    fighterDoctrine*: FighterDoctrineConfig
    advancedCarrierOperations*: AdvancedCarrierOpsConfig

