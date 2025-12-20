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
import ./core

type
  TechField* {.pure.} = enum
    ConstructionTech, WeaponsTech, TerraformingTech,
    ElectronicIntelligence, CloakingTech, ShieldTech,
    CounterIntelligence, FighterDoctrine, AdvancedCarrierOps

  TechLevel* = object
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

  ResearchPoints* = object
    economic*: int32
    science*: int32
    technology*: Table[TechField, int32]

  TechTree* = object
    houseId*: HouseId  # Add back-reference
    levels*: TechLevel
    accumulated*: ResearchPoints
    breakthroughBonus*: Table[TechField, float32]

  BreakthroughType* {.pure.} = enum
    Minor, Moderate, Major, Revolutionary

  RevolutionaryTech* {.pure.} = enum
    QuantumComputing, AdvancedStealth,
    TerraformingNexus, ExperimentalPropulsion

  ResearchCategory* {.pure.} = enum
    Economic, Science, Technology

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
    EconomicLevel, ScienceLevel, Technology

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
