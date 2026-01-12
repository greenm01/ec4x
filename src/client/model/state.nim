import std/[options]
import ../../engine/types/player_state # Reuse engine types where possible

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

  # The Root Model
  ClientModel* = object
    ui*: UiState
    playerState*: Option[PlayerState] # Loaded game data
    isConnected*: bool

proc initClientModel*(): ClientModel =
  result = ClientModel(
    ui: UiState(
      currentScreen: Screen.Login,
      debugCounter: 0,
      loginUrl: "http://localhost:8080",
      loginUsername: ""
    ),
    playerState: none(PlayerState),
    isConnected: false
  )
