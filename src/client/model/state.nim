import std/[options]
import ../../engine/types/player_state # Reuse engine types where possible
import ../starmap/[hex_math, camera, theme, renderer, input]

type
  Screen* {.pure.} = enum
    Login
    Dashboard
    Starmap
    Orders
    Settings

  # UI-specific state (selection, scroll position, input fields)
  UiState* = object
    currentScreen*: Screen
    debugCounter*: int # For Hello World test
    loginUrl*: string
    loginUsername*: string
    errorMessage*: Option[string]

  # Starmap display state
  StarmapState* = object
    camera*: Camera2D
    theme*: StarmapTheme
    renderData*: StarmapRenderData
    inputState*: StarmapInputState
    hoveredSystem*: Option[HexCoord]
    selectedSystem*: Option[HexCoord]

  # The Root Model
  ClientModel* = object
    ui*: UiState
    starmap*: StarmapState
    playerState*: Option[PlayerState] # Loaded game data
    isConnected*: bool

proc initStarmapState*(screenWidth, screenHeight: int32): StarmapState =
  ## Initialize starmap state with demo data for testing.
  result = StarmapState(
    camera: initCamera2D(screenWidth, screenHeight),
    theme: defaultTheme(),
    renderData: createDemoStarmap(),
    inputState: initInputState(),
    hoveredSystem: none(HexCoord),
    selectedSystem: none(HexCoord)
  )

proc initClientModel*(screenWidth: int32 = 1280,
    screenHeight: int32 = 720): ClientModel =
  result = ClientModel(
    ui: UiState(
      currentScreen: Screen.Login,
      debugCounter: 0,
      loginUrl: "http://localhost:8080",
      loginUsername: ""
    ),
    starmap: initStarmapState(screenWidth, screenHeight),
    playerState: none(PlayerState),
    isConnected: false
  )
