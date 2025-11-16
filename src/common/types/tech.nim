## EC4X Technology Types
## Tech fields and level definitions

# =============================================================================
# Technology Types
# =============================================================================

type
  TechField* {.pure.} = enum
    ## Seven tech fields in EC4X (hardcoded)
    EnergyLevel              # EL
    ShieldLevel              # SL
    ConstructionTech         # CST
    WeaponsTech              # WEP
    TerraformingTech         # TER
    ElectronicIntelligence   # ELI
    CounterIntelligence      # CIC

  TechLevel* = object
    ## Tech levels for all fields
    energyLevel*: int              # EL (0-10)
    shieldLevel*: int              # SL (0-10)
    constructionTech*: int         # CST (0-10)
    weaponsTech*: int              # WEP (0-10)
    terraformingTech*: int         # TER (0-10)
    electronicIntelligence*: int   # ELI (0-10)
    counterIntelligence*: int      # CIC (0-10)
