type
  LaneWeightsConfig* = object ## Jump lane type distribution weights
    majorWeight*: float32
    minorWeight*: float32
    restrictedWeight*: float32

  GenerationConfig* = object ## Map generation parameters
    useDistanceMaximization*: bool
    preferVertexPositions*: bool
    hubUsesMixedLanes*: bool

  HomeworldPlacementConfig* = object ## Homeworld placement parameters
    homeworldLaneCount*: int32 # Number of lanes per homeworld (default: 3)

  PlanetNamesConfig* = object ## Planet/colony naming
    names*: seq[string] # Pool of planet names to draw from

  StarmapConfig* = object ## Complete starmap configuration loaded from KDL
    laneWeights*: LaneWeightsConfig
    generation*: GenerationConfig
    homeworldPlacement*: HomeworldPlacementConfig
    planetNames*: PlanetNamesConfig

