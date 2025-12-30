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
    economicLevel*: int32
    scienceLevel*: int32
    weapons*: int32
    construction*: int32
    shields*: int32
    terraforming*: int32
    electronicIntelligence*: int32
    cloaking*: int32
    strategicLift*: int32
    counterIntelligence*: int32
    flagshipCommand*: int32
    strategicCommand*: int32
    fighterDoctrine*: int32
    advancedCarrierOperations*: int32

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
