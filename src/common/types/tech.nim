## EC4X Technology Types
## Tech fields and level definitions

# =============================================================================
# Technology Types
# =============================================================================

type
  TechField* {.pure.} = enum
    ## Eleven tech fields in EC4X (economy.md:4.0)
    EconomicLevel            # EL
    ScienceLevel             # SL
    ConstructionTech         # CST
    WeaponsTech              # WEP
    TerraformingTech         # TER
    ElectronicIntelligence   # ELI
    CloakingTech             # CLK
    ShieldTech               # SLD (Planetary Shields)
    CounterIntelligence      # CIC
    FighterDoctrine          # FD
    AdvancedCarrierOps       # ACO

  TechLevel* = object
    ## Tech levels for all fields
    economicLevel*: int            # EL (0-10)
    scienceLevel*: int             # SL (0-10)
    constructionTech*: int         # CST (0-10)
    weaponsTech*: int              # WEP (0-10)
    terraformingTech*: int         # TER (0-10)
    electronicIntelligence*: int   # ELI (0-10)
    cloakingTech*: int             # CLK (0-10)
    shieldTech*: int               # SLD (0-10): Planetary shield technology
    counterIntelligence*: int      # CIC (0-10)
    fighterDoctrine*: int          # FD (0-3): Fighter capacity multiplier
    advancedCarrierOps*: int       # ACO (0-3): Carrier hangar capacity
