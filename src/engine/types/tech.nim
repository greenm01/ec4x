## Tech & Research System Types
##
## Type definitions for R&D system per economy.md:4.0
##
## Core research concepts:
## - RP (Research Points): Investment in R&D
## - ERP (Economic Research Points): For Economic Level
## - SRP (Science Research Points): For Science Level + science techs
## - MRP (Military Research Points): For Military Level + military techs
## - Breakthroughs: Random research events (bi-annual)
import std/[tables, options]
import ./[core, prestige]

type
  TechField* {.pure.} = enum
    ConstructionTech       # CST
    WeaponsTech            # WEP
    TerraformingTech       # TER
    ElectronicIntelligence # ELI
    CloakingTech           # CLK
    ShieldTech             # SLD
    CounterIntelligence    # CIC
    StrategicLiftTech      # STL
    FlagshipCommandTech    # FC
    StrategicCommandTech   # SC
    FighterDoctrine        # FD
    AdvancedCarrierOps     # ACO

  TechLevel* = object
    ## Tech levels using standard abbreviations (see docs/specs/04-research_development.md)
    el*: int32   # Economic Level
    sl*: int32   # Science Level
    ml*: int32   # Military Level
    cst*: int32  # Construction Tech
    wep*: int32  # Weapons Tech
    ter*: int32  # Terraforming Tech
    eli*: int32  # Electronic Intelligence
    clk*: int32  # Cloaking Tech
    sld*: int32  # Shield Tech
    cic*: int32  # Counter Intelligence
    stl*: int32  # Strategic Lift Tech
    fc*: int32   # Flagship Command Tech
    sc*: int32   # Strategic Command Tech
    fd*: int32   # Fighter Doctrine
    aco*: int32  # Advanced Carrier Ops

  ResearchPoints* = object
    ## Shared pool accumulators: ERP, SRP, MRP
    erp*: int32   # Economic Research Points pool
    srp*: int32   # Science Research Points pool (SL + science techs)
    mrp*: int32   # Military Research Points pool (military techs)

  ResearchDeposits* = object
    ## PP deposited into pools this turn
    erp*: int32
    srp*: int32
    mrp*: int32

  TechPurchaseSet* = object
    ## Explicit tech purchases for this turn
    economic*: bool                    # Buy next EL
    science*: bool                     # Buy next SL
    military*: bool                    # Buy next ML
    technology*: set[TechField]        # Buy next level per field

  ResearchLiquidation* = object
    ## RP to liquidate from pools (converted back to PP at 2:1)
    erp*: int32
    srp*: int32
    mrp*: int32

  TechTree* = object
    houseId*: HouseId # Add back-reference
    levels*: TechLevel
    accumulated*: ResearchPoints
    breakthroughBonus*: Table[TechField, float32]

  BreakthroughType* {.pure.} = enum
    Minor
    Moderate
    Major
    Revolutionary

  RevolutionaryTech* {.pure.} = enum
    QuantumComputing
    AdvancedStealth
    TerraformingNexus
    ExperimentalPropulsion

  ResearchCategory* {.pure.} = enum
    Economic
    Science
    Technology

  BreakthroughEvent* = object
    houseId*: HouseId
    turn*: int32
    breakthroughType*: BreakthroughType
    category*: ResearchCategory
    amount*: int32
    costReduction*: float32
    autoAdvance*: bool
    revolutionary*: Option[RevolutionaryTech]

  ResearchAllocation* = object
    ## Legacy per-tech allocation (kept for save migration)
    economic*: int32
    science*: int32
    military*: int32
    technology*: Table[TechField, int32]

  AdvancementType* {.pure.} = enum
    EconomicLevel
    ScienceLevel
    MilitaryLevel
    Technology

  ResearchAdvancement* = object
    case advancementType*: AdvancementType
    of EconomicLevel:
      elFromLevel*: int32
      elToLevel*: int32
      elCost*: int32
    of ScienceLevel:
      slFromLevel*: int32
      slToLevel*: int32
      slCost*: int32
    of MilitaryLevel:
      mlFromLevel*: int32
      mlToLevel*: int32
      mlCost*: int32
    of Technology:
      techField*: TechField
      techFromLevel*: int32
      techToLevel*: int32
      techCost*: int32
    houseId*: HouseId
    prestigeEvent*: Option[PrestigeEvent]

  ResearchReport* = object
    turn*: int32
    allocations*: Table[HouseId, ResearchAllocation]
    breakthroughs*: seq[BreakthroughEvent]
    advancements*: seq[ResearchAdvancement]

proc researchPool*(field: TechField): ResearchCategory =
  ## Which pool funds this tech field
  case field
  of TerraformingTech, ElectronicIntelligence, CloakingTech,
     ShieldTech, CounterIntelligence, StrategicLiftTech: ResearchCategory.Science
  else: ResearchCategory.Technology

proc isSrpField*(field: TechField): bool =
  researchPool(field) == ResearchCategory.Science
