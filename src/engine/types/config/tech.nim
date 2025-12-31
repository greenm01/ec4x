## Tech configuration types
## Note: PlanetType is imported from economy config types

import std/tables
import ./economy
export PlanetType

type
  ElLevelData* = object
    ## Economic Level data (EL)
    slRequired*: int32
    erpCost*: int32
    multiplier*: float32

  SlLevelData* = object
    ## Science Level data (SL)
    erpRequired*: int32
    srpRequired*: int32

  WepLevelData* = object
    ## Weapons Tech level data (WEP)
    slRequired*: int32
    trpCost*: int32

  EliLevelData* = object
    ## Electronic Intelligence level data (ELI)
    slRequired*: int32
    srpCost*: int32

  ClkLevelData* = object
    ## Cloaking Tech level data (CLK)
    slRequired*: int32
    srpCost*: int32

  CicLevelData* = object
    ## Counter Intelligence level data (CIC)
    slRequired*: int32
    srpCost*: int32

  StlLevelData* = object
    ## Strategic Lift Tech level data (STL)
    slRequired*: int32
    srpCost*: int32

  TerLevelData* = object
    ## Terraforming Tech level data (TER)
    slRequired*: int32
    srpCost*: int32
    ppCost*: int32
    planetClass*: string

  SldLevelData* = object
    ## Shield Tech level data (SLD)
    slRequired*: int32
    srpCost*: int32
    absorption*: int32
    shieldDs*: int32
    d20Threshold*: int32
    hitsBlocked*: float32

  FcLevelData* = object
    ## Flagship Command level data (FC)
    slRequired*: int32
    trpCost*: int32
    crBonus*: int32

  ScLevelData* = object
    ## Strategic Command level data (SC)
    slRequired*: int32
    trpCost*: int32
    c2Bonus*: int32

  FdLevelData* = object
    ## Fighter Doctrine level data (FD)
    slRequired*: int32
    trpCost*: int32
    capacityMultiplier*: float32
    description*: string

  AcoLevelData* = object
    ## Advanced Carrier Operations level data (ACO)
    slRequired*: int32
    trpCost*: int32
    cvCapacity*: int32
    cxCapacity*: int32
    description*: string

  CstLevelData* = object
    ## Construction Tech level data (CST)
    slRequired*: int32
    trpCost*: int32
    unlocks*: seq[string]

  TerraformingUpgradeCostData* = object
    ## Data for terraforming upgrade costs per planet type
    terRequired*: int32
    puMin*: int32
    puMax*: int32
    ppCost*: int32

  ElConfig* = object
    ## Economic Level configuration (EL 2-10)
    levels*: Table[int32, ElLevelData]

  SlConfig* = object
    ## Science Level configuration (SL 2-10)
    levels*: Table[int32, SlLevelData]

  EliConfig* = object
    ## Electronic Intelligence configuration (ELI 1-15)
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, EliLevelData]

  ClkConfig* = object
    ## Cloaking Tech configuration (CLK 1-15)
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, ClkLevelData]

  CicConfig* = object
    ## Counter Intelligence configuration (CIC 1-15)
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, CicLevelData]

  StlConfig* = object
    ## Strategic Lift Tech configuration (STL 1-15)
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, StlLevelData]

  CstConfig* = object
    ## Construction Tech configuration (CST 2-10)
    baseModifier*: float32
    incrementPerLevel*: float32
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, CstLevelData]

  WepConfig* = object
    ## Weapons Tech configuration (WEP 2-10)
    weaponsStatIncreasePerLevel*: float32
    weaponsCostIncreasePerLevel*: float32
    levels*: Table[int32, WepLevelData]

  TerConfig* = object
    ## Terraforming Tech configuration (TER 1-6)
    levels*: Table[int32, TerLevelData]

  SldConfig* = object
    ## Shield Tech configuration (SLD 1-6)
    levels*: Table[int32, SldLevelData]

  FcConfig* = object
    ## Flagship Command configuration (FC 2-6)
    levels*: Table[int32, FcLevelData]

  ScConfig* = object
    ## Strategic Command configuration (SC 1-5)
    levels*: Table[int32, ScLevelData]

  FdConfig* = object
    ## Fighter Doctrine configuration (FD 2-3)
    levels*: Table[int32, FdLevelData]

  AcoConfig* = object
    ## Advanced Carrier Operations configuration (ACO 1-3)
    capacityMultiplierPerLevel*: float32
    levels*: Table[int32, AcoLevelData]

  TerCostsConfig* = object
    ## Terraforming upgrade costs by planet type
    costs*: array[PlanetType, TerraformingUpgradeCostData]

  TechConfig* = object
    ## Complete technology configuration loaded from KDL
    el*: ElConfig
    sl*: SlConfig
    cst*: CstConfig
    wep*: WepConfig
    ter*: TerConfig
    terCosts*: TerCostsConfig
    eli*: EliConfig
    clk*: ClkConfig
    sld*: SldConfig
    cic*: CicConfig
    stl*: StlConfig
    fc*: FcConfig
    sc*: ScConfig
    fd*: FdConfig
    aco*: AcoConfig
