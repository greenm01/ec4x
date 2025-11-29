## Research System Types
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
import ../../common/types/[core, tech]
import ../prestige

export core.HouseId
export tech.TechField, tech.TechLevel
export prestige.PrestigeEvent

type
  ## Research Point Categories

  ResearchCategory* {.pure.} = enum
    Economic,      # ERP: Economic Level upgrades
    Science,       # SRP: Science Level upgrades
    Technology     # TRP: Specific tech upgrades (WEP, ELI, etc.)

  ResearchAllocation* = object
    ## PP allocated to research this turn
    economic*: int      # PP → ERP
    science*: int       # PP → SRP
    technology*: Table[TechField, int]  # PP → TRP per field

  ResearchPoints* = object
    ## Accumulated research points
    economic*: int      # ERP accumulated
    science*: int       # SRP accumulated
    technology*: Table[TechField, int]  # TRP per field

  ## Tech Tree State

  TechTree* = object
    ## House technology tree
    levels*: TechLevel           # Current tech levels
    accumulated*: ResearchPoints # Accumulated RP towards next level
    breakthroughBonus*: Table[TechField, float]  # Active breakthrough bonuses

  ## Research Breakthroughs (economy.md:4.1.1)

  BreakthroughType* {.pure.} = enum
    Minor,           # +10 RP (0-4 on d10)
    Moderate,        # 20% cost reduction (5-6)
    Major,           # Auto-advance level (7-8)
    Revolutionary    # Unique tech unlock (9)

  RevolutionaryTech* {.pure.} = enum
    QuantumComputing,        # +10% EL_MOD permanently
    AdvancedStealth,         # Raiders +2 detection difficulty
    TerraformingNexus,       # +2% colony growth
    ExperimentalPropulsion   # Crippled ships cross restricted lanes

  BreakthroughEvent* = object
    ## Research breakthrough result
    houseId*: HouseId
    turn*: int
    breakthroughType*: BreakthroughType
    category*: ResearchCategory  # Which RP category affected
    amount*: int                 # RP bonus (for Minor)
    costReduction*: float        # Cost multiplier (for Moderate)
    autoAdvance*: bool           # Auto-level up (for Major)
    revolutionary*: Option[RevolutionaryTech]  # Unique tech (for Revolutionary)

  ## Research Advancement

  AdvancementType* {.pure.} = enum
    ## Type of research advancement
    EconomicLevel,    # EL advancement
    ScienceLevel,     # SL advancement
    Technology        # Tech field advancement

  ResearchAdvancement* = object
    ## Unified advancement event with type discrimination
    ## Separates EL/SL levels from technology fields per economy.md:4.2-4.3
    case advancementType*: AdvancementType
    of EconomicLevel:
      elFromLevel*: int
      elToLevel*: int
      elCost*: int      # ERP spent
    of ScienceLevel:
      slFromLevel*: int
      slToLevel*: int
      slCost*: int      # SRP spent
    of Technology:
      techField*: TechField
      techFromLevel*: int
      techToLevel*: int
      techCost*: int    # TRP spent

    houseId*: HouseId
    prestigeEvent*: Option[PrestigeEvent]

  # Legacy type alias for backwards compatibility during migration
  TechAdvancement* = ResearchAdvancement

  ResearchReport* = object
    ## Research phase report
    turn*: int
    allocations*: Table[HouseId, ResearchAllocation]
    breakthroughs*: seq[BreakthroughEvent]
    advancements*: seq[ResearchAdvancement]

## Constants per economy.md:4.0

const
  # Research upgrade cycles
  RESEARCH_UPGRADE_TURNS* = [1, 7]  # First and seventh month of year

  # Research breakthrough
  BASE_BREAKTHROUGH_CHANCE* = 0.10  # 10% base
  BREAKTHROUGH_BONUS_PER_50RP* = 0.01  # +1% per 50 RP invested (last 6 turns)

  # Economic Level costs (economy.md:4.2)
  EL_BASE_COST* = 50
  EL_COST_INCREMENT* = 10  # For EL1-5
  EL_COST_INCREMENT_HIGH* = 15  # For EL6+
  EL_MODIFIER_PER_LEVEL* = 0.05  # +5% per level
  EL_MAX_MODIFIER* = 0.50  # Cap at 50% (EL10+)

## Helper Procs

proc initDefaultTechLevel*(): TechLevel =
  ## Initialize TechLevel with all fields at starting level 1
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  result = TechLevel(
    economicLevel: 1,
    scienceLevel: 1,
    constructionTech: 1,
    weaponsTech: 1,
    terraformingTech: 1,
    electronicIntelligence: 1,
    cloakingTech: 1,
    shieldTech: 1,
    counterIntelligence: 1,
    fighterDoctrine: 1,
    advancedCarrierOps: 1
  )

proc initTechTree*(startingLevels: TechLevel): TechTree =
  ## Initialize tech tree with starting levels
  result = TechTree(
    levels: startingLevels,
    accumulated: ResearchPoints(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    ),
    breakthroughBonus: initTable[TechField, float]()
  )

proc initTechTree*(): TechTree =
  ## Initialize tech tree with default starting levels (all at 1)
  ## Convenience function for tests and scenarios
  result = initTechTree(initDefaultTechLevel())

proc initResearchAllocation*(): ResearchAllocation =
  ## Initialize empty research allocation
  result = ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )
