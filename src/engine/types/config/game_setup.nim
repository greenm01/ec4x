import std/options

type
  GameInfoConfig* = object ## Game metadata
    name*: string
    description*: string
    recommendedPlayers*: int32
    estimatedDuration*: string

  VictoryConditionsConfig* = object ## Victory conditions
    primaryCondition*: string
    secondaryCondition*: string
    prestigeThreshold*: int32
    turnLimit*: int32 # NEW: Turn limit for turn_limit victory mode

  MapConfig* = object ## Map generation settings
    size*: string
    systems*: int32
    jumpLaneDensity*: string
    startingDistance*: string

  StartingResourcesConfig* = object ## Starting economic resources
    treasury*: int32
    startingPrestige*: int32
    defaultTaxRate*: float32

  StartingTechConfig* = object ## Initial technology levels per gameplay.md:1.2
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

  StartingFleetConfig* = object ## Initial fleet composition
    fleetCount*: int32 # Number of individual fleets to create
    # Fallback aggregated counts (used if individual fleet sections not available)
    etac*: int32
    lightCruiser*: int32
    destroyer*: int32
    scout*: int32

  FleetConfig* = object ## Individual fleet configuration (new per-fleet format)
    ships*: seq[string] # Ship class names (e.g., ["ETAC", "LightCruiser"])
    cargoPtu*: Option[int32] # Optional PTU cargo override for ETACs

  HouseNamingConfig* = object ## House naming configuration
    namePattern*: string # Pattern with {index} placeholder
    useThemeNames*: bool # Whether to use house_themes.kdl

  StartingFacilitiesConfig* = object ## Homeworld starting facilities
    spaceports*: int32
    shipyards*: int32
    starbases*: int32
    groundBatteries*: int32
    planetaryShields*: int32

  StartingGroundForcesConfig* = object ## Homeworld starting ground forces
    armies*: int32
    marines*: int32

  HomeworldConfig* = object ## Homeworld characteristics
    planetClass*: string # "Eden"
    rawQuality*: string # "Abundant"
    colonyLevel*: int32 # Infrastructure level (5 = Level V)
    populationUnits*: int32 # Starting population in PU (840)
    industrialUnits*: int32

  GameSetupConfig* = object ## Complete game setup configuration
    gameInfo*: GameInfoConfig
    victoryConditions*: VictoryConditionsConfig
    map*: MapConfig
    startingResources*: StartingResourcesConfig
    startingTech*: StartingTechConfig
    startingFleet*: StartingFleetConfig
    startingFacilities*: StartingFacilitiesConfig
    startingGroundForces*: StartingGroundForcesConfig
    homeworld*: HomeworldConfig
    houseNaming*: Option[HouseNamingConfig] # Optional, defaults if not present

