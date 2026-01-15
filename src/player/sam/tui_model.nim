## TUI Model - Application state for EC4X TUI
##
## This module defines the complete application model for the TUI player,
## combining both game state and UI state into a single structure that
## the SAM pattern can manage.
##
## The model is the single source of truth for the entire application.

import std/[options, tables]
# Note: types module is not directly used here but provides shared types
# that may be used by consumers of this module

type
  ViewMode* {.pure.} = enum
    ## Current UI mode/view
    Map        ## Navigating the starmap
    Colonies   ## Colony list
    Fleets     ## Fleet list
    Orders     ## Pending orders
    Systems    ## System list with connectivity

  # Re-export hex coordinate for convenience
  HexCoord* = tuple[q, r: int]
  
  HexDirection* = enum
    ## Movement directions on hex grid
    East, NorthEast, NorthWest, West, SouthWest, SouthEast

  SystemInfo* = object
    ## Minimal system info for rendering (decoupled from engine types)
    id*: int
    name*: string
    coords*: HexCoord
    ring*: int
    planetClass*: int       ## 0=Extreme to 6=Eden
    resourceRating*: int    ## 0=VeryPoor to 4=VeryRich
    owner*: Option[int]     ## House ID if colonized
    isHomeworld*: bool
    isHub*: bool
    fleetCount*: int        ## Number of fleets present

  ColonyInfo* = object
    ## Colony info for list display
    systemId*: int
    systemName*: string
    population*: int
    production*: int
    owner*: int

  FleetInfo* = object
    ## Fleet info for list display
    id*: int
    location*: int          ## System ID
    locationName*: string
    shipCount*: int
    owner*: int

  OrderInfo* = object
    ## Pending order info
    id*: int
    orderType*: string
    description*: string

  MapState* = object
    ## Hex map navigation state
    cursor*: HexCoord
    selected*: Option[HexCoord]
    viewportOrigin*: HexCoord

  # ============================================================================
  # The Complete TUI Model
  # ============================================================================

  TuiModel* = object
    ## Complete application state for TUI player
    
    # -------------
    # UI State
    # -------------
    mode*: ViewMode               ## Current view mode
    selectedIdx*: int             ## Selected index in current list
    mapState*: MapState           ## Hex map navigation state
    
    # Terminal dimensions
    termWidth*: int
    termHeight*: int
    
    # Status flags
    running*: bool                ## Application running
    needsResize*: bool            ## Terminal was resized
    statusMessage*: string        ## Status bar message
    
    # Map export flags (processed by main loop with GameState access)
    exportMapRequested*: bool     ## Export SVG starmap
    openMapRequested*: bool       ## Export and open in viewer
    lastExportPath*: string       ## Path to last exported SVG
    
    # -------------
    # Game Data (View Layer - decoupled from engine)
    # -------------
    turn*: int
    viewingHouse*: int            ## Player's house ID
    houseName*: string
    treasury*: int
    prestige*: int
    
    # Collections for display
    systems*: Table[HexCoord, SystemInfo]
    colonies*: seq[ColonyInfo]
    fleets*: seq[FleetInfo]
    orders*: seq[OrderInfo]
    
    maxRing*: int                 ## Max ring for starmap
    homeworld*: Option[HexCoord]  ## Player's homeworld location

# ============================================================================
# Model Initialization
# ============================================================================

proc hexCoord*(q, r: int): HexCoord =
  ## Create a hex coordinate
  (q, r)

proc initMapState*(cursor: HexCoord = (0, 0)): MapState =
  ## Create initial map state
  MapState(
    cursor: cursor,
    selected: none(HexCoord),
    viewportOrigin: (0, 0)
  )

proc initTuiModel*(): TuiModel =
  ## Create initial TUI model with defaults
  TuiModel(
    mode: ViewMode.Colonies,
    selectedIdx: 0,
    mapState: initMapState(),
    termWidth: 80,
    termHeight: 24,
    running: true,
    needsResize: false,
    statusMessage: "",
    turn: 1,
    viewingHouse: 1,
    houseName: "Unknown",
    treasury: 0,
    prestige: 0,
    systems: initTable[HexCoord, SystemInfo](),
    colonies: @[],
    fleets: @[],
    orders: @[],
    maxRing: 3,
    homeworld: none(HexCoord)
  )

# ============================================================================
# Hex Navigation Helpers
# ============================================================================

proc neighbor*(coord: HexCoord, dir: HexDirection): HexCoord =
  ## Get neighboring hex in given direction
  ## Uses axial coordinates with flat-top orientation
  case dir
  of HexDirection.East:       (coord.q + 1, coord.r)
  of HexDirection.West:       (coord.q - 1, coord.r)
  of HexDirection.NorthEast:  (coord.q + 1, coord.r - 1)
  of HexDirection.NorthWest:  (coord.q, coord.r - 1)
  of HexDirection.SouthEast:  (coord.q, coord.r + 1)
  of HexDirection.SouthWest:  (coord.q - 1, coord.r + 1)

# ============================================================================
# Model Queries
# ============================================================================

proc currentListLength*(model: TuiModel): int =
  ## Get length of current list based on mode
  case model.mode
  of ViewMode.Colonies: model.colonies.len
  of ViewMode.Fleets: model.fleets.len
  of ViewMode.Orders: model.orders.len
  of ViewMode.Systems: model.systems.len
  of ViewMode.Map: 0

proc systemAt*(model: TuiModel, coord: HexCoord): Option[SystemInfo] =
  ## Get system at coordinate
  if model.systems.hasKey(coord):
    some(model.systems[coord])
  else:
    none(SystemInfo)

proc cursorSystem*(model: TuiModel): Option[SystemInfo] =
  ## Get system at cursor
  model.systemAt(model.mapState.cursor)

proc selectedColony*(model: TuiModel): Option[ColonyInfo] =
  ## Get selected colony
  if model.mode == ViewMode.Colonies and model.selectedIdx < model.colonies.len:
    some(model.colonies[model.selectedIdx])
  else:
    none(ColonyInfo)

proc selectedFleet*(model: TuiModel): Option[FleetInfo] =
  ## Get selected fleet
  if model.mode == ViewMode.Fleets and model.selectedIdx < model.fleets.len:
    some(model.fleets[model.selectedIdx])
  else:
    none(FleetInfo)

proc ownedColonyCoords*(model: TuiModel): seq[HexCoord] =
  ## Get coordinates of all owned colonies
  result = @[]
  for sys in model.systems.values:
    if sys.owner.isSome and sys.owner.get == model.viewingHouse:
      result.add(sys.coords)
