## Tech & Research System Types
##
## Type definitions for R&D system per economy.md:4.0
##
## Core research concepts:
## - RP (Research Points): Investment in R&D
## - ERP (Economic Research Points): For Economic Level
## - SRP (Science Research Points): For Science Level
## - TRP (Technology Research Points): For specific technologies
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
    economic*: int32
    science*: int32
    technology*: Table[TechField, int32]

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
    economic*: int32
    science*: int32
    technology*: Table[TechField, int32]

  AdvancementType* {.pure.} = enum
    EconomicLevel
    ScienceLevel
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
