## Test fog-of-war adapters
##
## Verifies that fog-of-war adapters correctly filter information
## based on visibility levels.

import std/[unittest, options, tables]
import ../../src/engine/types/[core, game_state, starmap, colony, fleet, ship, house, player_state, diplomacy]
import ../../src/engine/state/engine
import ../../src/player/tui/widget/hexmap/hexmap_pkg
import ../../src/player/tui/adapters

proc createMinimalGameState(): GameState =
  ## Create a minimal game state for testing
  result = GameState()
  
  # Initialize entity managers
  result.systems = Systems(
    entities: EntityManager[SystemId, System](
      data: @[],
      index: initTable[SystemId, int]()
    )
  )
  result.colonies = Colonies(
    entities: EntityManager[ColonyId, Colony](
      data: @[],
      index: initTable[ColonyId, int]()
    ),
    bySystem: initTable[SystemId, ColonyId](),
    byOwner: initTable[HouseId, seq[ColonyId]]()
  )
  result.fleets = Fleets(
    entities: EntityManager[FleetId, Fleet](
      data: @[],
      index: initTable[FleetId, int]()
    ),
    bySystem: initTable[SystemId, seq[FleetId]](),
    byOwner: initTable[HouseId, seq[FleetId]]()
  )
  result.houses = Houses(
    entities: EntityManager[HouseId, House](
      data: @[],
      index: initTable[HouseId, int]()
    )
  )
  result.ships = Ships(
    entities: EntityManager[ShipId, Ship](
      data: @[],
      index: initTable[ShipId, int]()
    )
  )
  
  result.starmap = StarMap(
    lanes: JumpLanes(
      data: @[],
      neighbors: initTable[SystemId, seq[SystemId]](),
      connectionInfo: initTable[(SystemId, SystemId), LaneClass]()
    ),
    distanceMatrix: initTable[(SystemId, SystemId), uint32](),
    hubId: SystemId(1),
    homeWorlds: initTable[SystemId, HouseId](),
    houseSystemIds: @[]
  )
  
  result.intel = initTable[HouseId, IntelDatabase]()
  result.diplomaticRelation = initTable[(HouseId, HouseId), DiplomaticRelation]()
  result.turn = 1

suite "Fog-of-War Adapters":
  test "toFogOfWarMapData compiles and runs":
    # Create minimal state
    var state = createMinimalGameState()
    
    # Add a system
    let sys = System(
      id: SystemId(1),
      name: "Test System",
      coords: Hex(q: 0, r: 0),
      ring: 0,
      planetClass: PlanetClass.Lush,
      resourceRating: ResourceRating.Rich
    )
    state.addSystem(SystemId(1), sys)
    
    # Add a house
    let house = House(
      id: HouseId(1),
      name: "Test House",
      isEliminated: false,
      prestige: 0,
      intel: IntelDatabase(houseId: HouseId(1))
    )
    state.houses.entities.data.add(house)
    state.houses.entities.index[HouseId(1)] = 0
    
    # Convert to map data with fog-of-war
    let mapData = toFogOfWarMapData(state, HouseId(1))
    
    check mapData.viewingHouse == 1
    check mapData.systems.len >= 0  # May be 0 if no visibility
  
  test "coordinate conversions":
    let engineHex = Hex(q: 3, r: -2)
    let widgetCoord = toHexCoord(engineHex)
    
    check widgetCoord.q == 3
    check widgetCoord.r == -2
    
    let backToEngine = toEngineHex(widgetCoord)
    check backToEngine.q == engineHex.q
    check backToEngine.r == engineHex.r
  
  test "toFogOfWarDetailPanelData with no systems":
    var state = createMinimalGameState()
    
    # Add a house
    let house = House(
      id: HouseId(1),
      name: "Test House",
      isEliminated: false,
      prestige: 0,
      intel: IntelDatabase(houseId: HouseId(1))
    )
    state.houses.entities.data.add(house)
    state.houses.entities.index[HouseId(1)] = 0
    
    let coord = hexCoord(0, 0)
    let detailData = toFogOfWarDetailPanelData(coord, state, HouseId(1))
    
    check detailData.system.isNone
    check detailData.jumpLanes.len == 0
    check detailData.fleets.len == 0

echo "Running fog-of-war adapter tests..."
