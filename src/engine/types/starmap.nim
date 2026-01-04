## Map-related type definitions for EC4X
##
## This module contains the type definitions for the hexagonal grid (Hex),
## star systems (System), jump lanes (JumpLane), and other related map types.
import std/tables
import ./core

type
  Hex* = object
    q*: int32
    r*: int32

  System* = object
    id*: SystemId
    name*: string # Planet/system name from config
    coords*: Hex
    ring*: uint32
    # house removed - system controlled only if colony exists (use Colony.owner)
    planetClass*: PlanetClass
    resourceRating*: ResourceRating

  Systems* = object
    entities*: EntityManager[SystemId, System]

  LaneClass* {.pure.} = enum
    ## Jump lane classifications
    ## Determines movement restrictions per game specs
    Major ## Standard lanes, 2 jumps/turn if owned
    Minor ## 1 jump/turn
    Restricted ## 1 jump/turn, no crippled/transport ships

  JumpLane* = object
    source*: SystemId
    destination*: SystemId
    laneType*: LaneClass

  JumpLanes* = object
    data*: seq[JumpLane]
    # Fast adjacency lookup: SystemId -> List of neighboring SystemIds
    neighbors*: Table[SystemId, seq[SystemId]]
    # Fast lookup for lane properties between two points
    # (source, dest) -> LaneClass
    connectionInfo*: Table[(SystemId, SystemId), LaneClass]

  PathResult* = object
    path*: seq[SystemId]
    totalCost*: uint32
    found*: bool

  StarMapError* = object of CatchableError

  StarMap* = object
    lanes*: JumpLanes  # DoD: Indexed collection with neighbors/connectionInfo
    distanceMatrix*: Table[(SystemId, SystemId), uint32]  # Pre-computed hex distances
    hubId*: SystemId
    homeWorlds*: Table[SystemId, HouseId]
    houseSystemIds*: seq[SystemId]                     

  PlanetClass* {.pure.} = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    Extreme  # Level I   - 1-20 PU
    Desolate # Level II  - 21-60 PU
    Hostile  # Level III - 61-180 PU
    Harsh    # Level IV  - 181-500 PU
    Benign   # Level V   - 501-1000 PU
    Lush     # Level VI  - 1k-2k PU
    Eden     # Level VII - 2k+ PU

  ResourceRating* {.pure.} = enum
    ## System resource availability
    VeryPoor
    Poor
    Abundant
    Rich
    VeryRich
