## Map-related type definitions for EC4X
##
## This module contains the type definitions for the hexagonal grid (Hex),
## star systems (System), jump lanes (JumpLane), and other related map types.
import std/[tables, options]
import ./core

type
  Hex* = object
    q*: int32
    r*: int32

  System* = object
    id*: SystemId
    coords*: Hex
    ring*: uint32
    player*: Option[PlayerId]
    planetClass*: PlanetClass
    resourceRating*: ResourceRating

  Systems* = object
    entities*: EntityManager[SystemId, System]

  LaneType* {.pure.} = enum
    ## Jump lane classifications
    ## Determines movement restrictions per game specs
    Major ## Standard lanes, 2 jumps/turn if owned
    Minor ## 1 jump/turn
    Restricted ## 1 jump/turn, no crippled/transport ships

  JumpLane* = object
    source*: SystemId
    destination*: SystemId
    laneType*: LaneType

  JumpLanes* = object
    data*: seq[JumpLane]
    # Fast adjacency lookup: SystemId -> List of neighboring SystemIds
    neighbors*: Table[SystemId, seq[SystemId]]
    # Fast lookup for lane properties between two points
    # (source, dest) -> LaneType
    connectionInfo*: Table[(SystemId, SystemId), LaneType]

  PathResult* = object
    path*: seq[SystemId]
    totalCost*: uint32
    found*: bool

  StarMap* = object
    systems*: Systems
    lanes*: JumpLanes
    distanceMatrix*: Table[(SystemId, SystemId), uint32]
    playerCount*: int32
    numRings*: uint32
    hubId*: SystemId # Not uint
    playerSystemIds*: seq[SystemId] # Not uint
    seed*: int64

  PlanetClass* {.pure.} = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    Extreme # Level I   - 1-20 PU
    Desolate # Level II  - 21-60 PU
    Hostile # Level III - 61-180 PU
    Harsh # Level IV  - 181-500 PU
    Benign # Level V   - 501-1000 PU
    Lush # Level VI  - 1k-2k PU
    Eden # Level VII - 2k+ PU

  ResourceRating* {.pure.} = enum
    ## System resource availability
    VeryPoor
    Poor
    Abundant
    Rich
    VeryRich
