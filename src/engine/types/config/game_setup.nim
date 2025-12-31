import std/options

type
  GameParametersConfig* = object ## Game metadata
    scenarioName*: string ## Display name for this scenario
    scenarioDescription*: string ## Description of this scenario
    playerCount*: int32
    gameSeed*: Option[int64]

  VictoryConditionsConfig* = object ## Victory conditions
    turnLimit*: int32
    finalConflictAutoEnemy*: bool

  StartingResourcesConfig* = object ## Starting economic resources
    treasury*: int32
    startingPrestige*: int32
    defaultTaxRate*: float32

  StartingTechConfig* = object ## Initial technology levels per gameplay.md:1.2
    ## Uses standard tech abbreviations (see docs/specs/04-research_development.md)
    el*: int32   # Economic Level
    sl*: int32   # Science Level
    wep*: int32  # Weapons Tech
    cst*: int32  # Construction Tech
    sld*: int32  # Shield Tech
    ter*: int32  # Terraforming Tech
    eli*: int32  # Electronic Intelligence
    clk*: int32  # Cloaking Tech
    stl*: int32  # Strategic Lift Tech
    cic*: int32  # Counter Intelligence
    fc*: int32   # Flagship Command Tech
    sc*: int32   # Strategic Command Tech
    fd*: int32   # Fighter Doctrine
    aco*: int32  # Advanced Carrier Ops

  FleetConfig* = object ## Individual fleet configuration
    ships*: seq[string] # Ship class names (e.g., ["ETAC", "LightCruiser"])

  StartingFleetsConfig* = object ## Initial fleet composition
    fleets*: seq[FleetConfig] # List of starting fleets

  StartingFacilitiesConfig* = object ## Homeworld starting facilities
    spaceports*: int32
    shipyards*: int32
    drydocks*: int32

  StartingGroundForcesConfig* = object ## Homeworld starting ground forces
    armies*: int32
    marines*: int32
    groundBatteries*: int32
    planetaryShields*: int32

  MapGenerationConfig* = object ## Map size configuration
    numRings*: int32 # Number of hex rings (2-12 absolute bounds)

  HomeworldConfig* = object ## Homeworld characteristics
    planetClass*: string # "Eden"
    rawQuality*: string # "Abundant"
    colonyLevel*: int32 # Infrastructure level (5 = Level V)
    populationUnits*: int32 # Starting population in PU (840)
    industrialUnits*: int32
