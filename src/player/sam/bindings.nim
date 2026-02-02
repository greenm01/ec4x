## Keybinding Registry - Single Source of Truth
##
## This module defines all keybindings for the TUI. Both the status bar
## display and the input handler use this registry, ensuring they stay
## in sync. Inspired by Zellij's keybinding system.
##
## Key concepts:
## - Bindings are defined once and used for both display and input
## - Each binding has a context (where it's active)
## - Bindings have long and short labels for adaptive width rendering
## - Common modifiers (e.g., Ctrl) can be factored out in display

import std/[algorithm, options, sequtils]
import ./types
import ./tui_model
import ./actions

export types, tui_model, actions

# =============================================================================
# Types
# =============================================================================

type
  KeyModifier* {.pure.} = enum
    None
    Ctrl
    Alt
    Shift

  BindingContext* {.pure.} = enum
    ## Where a binding is active
    Global        ## Available everywhere (view tabs, quit, expert mode)
    Overview      ## Overview-specific actions
    Planets       ## Planets list
    PlanetDetail  ## Planet detail view
    Fleets        ## Fleets list
    FleetDetail   ## Fleet detail view
    Research      ## Research view
    Espionage     ## Espionage view
    Economy       ## Economy view
    Reports       ## Reports list
    ReportDetail  ## Report detail view
    Messages      ## Messages view
    Settings      ## Settings view
    Lobby         ## Entry screen / lobby
    OrderEntry    ## Order entry mode (target selection)
    ExpertMode    ## Expert command mode
    BuildModal    ## Build command modal

  Binding* = object
    key*: actions.KeyCode
    modifier*: KeyModifier
    actionKind*: ActionKind   ## Enum-based action identifier
    longLabel*: string        ## Full label: "VIEW COLONY"
    shortLabel*: string       ## Short label: "VIEW"
    context*: BindingContext
    priority*: int            ## Display order (lower = first)
    enabledCheck*: string     ## Name of condition check (empty = always)

  BarItemMode* {.pure.} = enum
    Unselected
    UnselectedAlt   ## Alternating background for visual rhythm
    Selected        ## Currently active/highlighted
    Disabled        ## Greyed out

  BarItem* = object
    keyDisplay*: string       ## Formatted key: "1", "Enter", "↑↓"
    label*: string            ## Current label (adapts to width)
    longLabel*: string        ## Full label for width calculation
    shortLabel*: string       ## Short label for narrow terminals
    mode*: BarItemMode
    binding*: Binding         ## Source binding

# =============================================================================
# Global Registry
# =============================================================================

var gBindings: seq[Binding] = @[]

proc clearBindings*() =
  ## Clear all bindings (for testing)
  gBindings = @[]

proc hasColonies*(model: TuiModel): bool = model.view.colonies.len > 0
proc hasFleets*(model: TuiModel): bool = model.view.fleets.len > 0
proc hasSelection*(model: TuiModel): bool = model.ui.selectedIdx >= 0
proc hasColonySelection*(model: TuiModel): bool =
  if model.ui.mode != ViewMode.Planets:
    return false
  if model.ui.selectedIdx < 0 or
      model.ui.selectedIdx >= model.view.planetsRows.len:
    return false
  let row = model.view.planetsRows[model.ui.selectedIdx]
  row.colonyId.isSome and row.isOwned
proc hasFleetSelection*(model: TuiModel): bool =
  model.ui.selectedFleetIds.len > 0
proc inGame*(model: TuiModel): bool = model.ui.appPhase == AppPhase.InGame
proc inLobby*(model: TuiModel): bool = model.ui.appPhase == AppPhase.Lobby

proc registerBinding*(b: Binding) =
  ## Legacy overload for Binding constructor
  gBindings.add(b)

proc registerBinding*(key: actions.KeyCode,
    modifier: KeyModifier = KeyModifier.None, actionKind: ActionKind,
    context: BindingContext, longLabel: string, shortLabel: string = "",
    priority: int = 0, enabledCheck: string = "") =
  ## Register a new binding using enum actionKind (new signature)
  gBindings.add(Binding(
    key: key,
    modifier: modifier,
    actionKind: actionKind,
    longLabel: longLabel,
    shortLabel: shortLabel,
    context: context,
    priority: priority,
    enabledCheck: enabledCheck
  ))


proc getAllBindings*(): seq[Binding] =
  ## Get all registered bindings
  gBindings

# =============================================================================
# Key Formatting
# =============================================================================

proc formatKeyCode*(key: actions.KeyCode): string =
  ## Format a key code for display (without modifier)
  case key
  of actions.KeyCode.Key1: "1"
  of actions.KeyCode.Key2: "2"
  of actions.KeyCode.Key3: "3"
  of actions.KeyCode.Key4: "4"
  of actions.KeyCode.Key5: "5"
  of actions.KeyCode.Key6: "6"
  of actions.KeyCode.Key7: "7"
  of actions.KeyCode.Key8: "8"
  of actions.KeyCode.Key9: "9"
  of actions.KeyCode.KeyQ: "q"
  of actions.KeyCode.KeyC: "c"
  of actions.KeyCode.KeyF: "f"
  of actions.KeyCode.KeyO: "o"
  of actions.KeyCode.KeyM: "m"
  of actions.KeyCode.KeyE: "e"
  of actions.KeyCode.KeyH: "h"
  of actions.KeyCode.KeyX: "x"
  of actions.KeyCode.KeyS: "s"
  of actions.KeyCode.KeyL: "l"
  of actions.KeyCode.KeyB: "b"
  of actions.KeyCode.KeyG: "g"
  of actions.KeyCode.KeyR: "r"
  of actions.KeyCode.KeyJ: "j"
  of actions.KeyCode.KeyD: "d"
  of actions.KeyCode.KeyP: "p"
  of actions.KeyCode.KeyV: "v"
  of actions.KeyCode.KeyN: "n"
  of actions.KeyCode.KeyW: "w"
  of actions.KeyCode.KeyI: "i"
  of actions.KeyCode.KeyT: "t"
  of actions.KeyCode.KeyA: "a"
  of actions.KeyCode.KeyY: "y"
  of actions.KeyCode.KeyU: "u"
  of actions.KeyCode.KeyUp: "↑"
  of actions.KeyCode.KeyDown: "↓"
  of actions.KeyCode.KeyLeft: "←"
  of actions.KeyCode.KeyRight: "→"
  of actions.KeyCode.KeyEnter: "Enter"
  of actions.KeyCode.KeyEscape: "Esc"
  of actions.KeyCode.KeyTab: "Tab"
  of actions.KeyCode.KeyShiftTab: "S-Tab"
  of actions.KeyCode.KeyHome: "Home"
  of actions.KeyCode.KeyBackspace: "Bksp"
  of actions.KeyCode.KeyPageUp: "PgUp"
  of actions.KeyCode.KeyPageDown: "PgDn"
  of actions.KeyCode.KeyColon: ":"
  of actions.KeyCode.KeyCtrlE: "e"
  of actions.KeyCode.KeyCtrlL: "l"
  of actions.KeyCode.KeyCtrlQ: "q"
  of actions.KeyCode.KeyNone: ""

proc formatModifier*(m: KeyModifier): string =
  ## Format a modifier for display
  case m
  of KeyModifier.None: ""
  of KeyModifier.Ctrl: "Ctrl"
  of KeyModifier.Alt: "Alt"
  of KeyModifier.Shift: "Shift"

proc formatKey*(key: actions.KeyCode, modifier: KeyModifier): string =
  ## Format a key with modifier for display
  ## Returns "Ctrl+q" or just "Enter" etc.
  let keyStr = formatKeyCode(key)
  if modifier == KeyModifier.None:
    keyStr
  else:
    formatModifier(modifier) & "+" & keyStr

proc formatKeyAngle*(key: actions.KeyCode, modifier: KeyModifier): string =
  ## Format a key with angle brackets: "<1>" or "<Ctrl+q>"
  "<" & formatKey(key, modifier) & ">"

# =============================================================================
# Context Mapping
# =============================================================================

proc viewModeToContext*(mode: ViewMode): BindingContext =
  ## Map a ViewMode to its binding context
  case mode
  of ViewMode.Overview: BindingContext.Overview
  of ViewMode.Planets: BindingContext.Planets
  of ViewMode.Fleets: BindingContext.Fleets
  of ViewMode.Research: BindingContext.Research
  of ViewMode.Espionage: BindingContext.Espionage
  of ViewMode.Economy: BindingContext.Economy
  of ViewMode.Reports: BindingContext.Reports
  of ViewMode.Messages: BindingContext.Messages
  of ViewMode.Settings: BindingContext.Settings
  of ViewMode.PlanetDetail: BindingContext.PlanetDetail
  of ViewMode.FleetDetail: BindingContext.FleetDetail
  of ViewMode.ReportDetail: BindingContext.ReportDetail

proc contextToViewMode*(ctx: BindingContext): Option[ViewMode] =
  ## Map a binding context to ViewMode (if applicable)
  case ctx
  of BindingContext.Overview: some(ViewMode.Overview)
  of BindingContext.Planets: some(ViewMode.Planets)
  of BindingContext.Fleets: some(ViewMode.Fleets)
  of BindingContext.Research: some(ViewMode.Research)
  of BindingContext.Espionage: some(ViewMode.Espionage)
  of BindingContext.Economy: some(ViewMode.Economy)
  of BindingContext.Reports: some(ViewMode.Reports)
  of BindingContext.Messages: some(ViewMode.Messages)
  of BindingContext.Settings: some(ViewMode.Settings)
  of BindingContext.PlanetDetail: some(ViewMode.PlanetDetail)
  of BindingContext.FleetDetail: some(ViewMode.FleetDetail)
  of BindingContext.ReportDetail: some(ViewMode.ReportDetail)
  else: none(ViewMode)

# =============================================================================
# Enabled Checks
# =============================================================================

proc isBindingEnabled*(b: Binding, model: TuiModel): bool =
  ## Check if a binding is enabled based on model state
  if b.enabledCheck.len == 0:
    return true

  case b.enabledCheck
  of "hasColonies":
    model.view.colonies.len > 0
  of "hasColonySelection":
    model.hasColonySelection()
  of "hasFleets":
    model.view.fleets.len > 0
  of "hasSelection":
    model.ui.selectedIdx >= 0
  of "hasFleetSelection":
    model.ui.selectedFleetIds.len > 0
  of "inGame":
    model.ui.appPhase == AppPhase.InGame
  of "inLobby":
    model.ui.appPhase == AppPhase.Lobby
  of "noSubModal":
    model.ui.fleetDetailModal.subModal == FleetSubModal.None
  else:
    true

# =============================================================================
# Binding Queries
# =============================================================================

proc getBindingsForContext*(ctx: BindingContext): seq[Binding] =
  ## Get all bindings for a specific context, sorted by priority
  result = gBindings.filterIt(it.context == ctx)
  result.sort(proc(a, b: Binding): int = cmp(a.priority, b.priority))

proc getGlobalBindings*(): seq[Binding] =
  ## Get all global bindings (view tabs, quit, expert mode)
  getBindingsForContext(BindingContext.Global)

proc findBinding*(key: actions.KeyCode, modifier: KeyModifier,
    ctx: BindingContext, model: TuiModel): Option[Binding] =
  ## Find the best binding by key, modifier, and context
  ## Returns the highest-priority enabled binding that matches
  var bestBinding: Option[Binding] = none(Binding)
  var bestPriority = -1
  
  for b in gBindings:
    if b.key == key and b.modifier == modifier and b.context == ctx:
      # Check if this binding is enabled
      if isBindingEnabled(b, model):
        # Keep track of highest priority enabled binding
        if b.priority > bestPriority:
          bestBinding = some(b)
          bestPriority = b.priority
  
  bestBinding

proc findGlobalBinding*(key: actions.KeyCode,
    modifier: KeyModifier, model: TuiModel): Option[Binding] =
  ## Find a global binding by key and modifier
  findBinding(key, modifier, BindingContext.Global, model)

# =============================================================================
# Binding Definitions
# =============================================================================

proc initBindings*() =
  ## Initialize all keybindings
  ## Called once at startup

  clearBindings()

  # =========================================================================
  # Global Bindings (View Tabs) - Always visible in game
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyO, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "OVERVIEW", shortLabel: "Ovrw", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "COLONY", shortLabel: "Col", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyF, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "FLEETS", shortLabel: "Flt", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyT, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "TECH", shortLabel: "Tech", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "ESPIONAGE", shortLabel: "Esp", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyG, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "GENERAL", shortLabel: "Gen", priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "REPORTS", shortLabel: "Rpt", priority: 7))

  registerBinding(Binding(
    key: KeyCode.KeyI, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "INTEL DB", shortLabel: "Intel", priority: 8))

  registerBinding(Binding(
    key: KeyCode.KeyS, modifier: KeyModifier.Alt,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "SETTINGS", shortLabel: "Set", priority: 9))

  registerBinding(Binding(
    key: KeyCode.KeyColon, modifier: KeyModifier.None,
    actionKind: ActionKind.enterExpertMode,
    context: BindingContext.Global,
    longLabel: "EXPERT", shortLabel: "Exp", priority: 100))

  registerBinding(Binding(
    key: KeyCode.KeyQ, modifier: KeyModifier.Alt,
    actionKind: ActionKind.quit,
    context: BindingContext.Global,
    longLabel: "QUIT", shortLabel: "Quit", priority: 101))

  # =========================================================================
  # Overview Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Overview,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Overview,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Overview,
    longLabel: "JUMP", shortLabel: "Jump", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.navigateMode,
    context: BindingContext.Overview,
    longLabel: "DIPLOMACY", shortLabel: "Dipl", priority: 20))

  # =========================================================================
  # Planets Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Planets,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Planets,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Planets,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Planets,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Planets,
    longLabel: "VIEW", shortLabel: "View", priority: 10,
    enabledCheck: "hasColonySelection"))

  registerBinding(Binding(
    key: KeyCode.KeyB, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Planets,
    longLabel: "BUILD", shortLabel: "Bld", priority: 20,
    enabledCheck: "hasColonySelection"))

  # =========================================================================
  # Planet Detail Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "PREV TAB", shortLabel: "←", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "NEXT TAB", shortLabel: "→", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "NEXT TAB", shortLabel: "Tab", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyS, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "SUMMARY", shortLabel: "Sum", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "ECONOMY", shortLabel: "Eco", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "CONSTRUCTION", shortLabel: "Con", priority: 12))

  registerBinding(Binding(
    key: KeyCode.KeyD, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "DEFENSE", shortLabel: "Def", priority: 13))

  registerBinding(Binding(
    key: KeyCode.KeyG, modifier: KeyModifier.None,
    actionKind: ActionKind.switchPlanetTab,
    context: BindingContext.PlanetDetail,
    longLabel: "SETTINGS", shortLabel: "Set", priority: 14))

  registerBinding(Binding(
    key: KeyCode.KeyB, modifier: KeyModifier.None,
    actionKind: ActionKind.openBuildModal,
    context: BindingContext.PlanetDetail,
    longLabel: "BUILD", shortLabel: "Bld", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.breadcrumbBack,
    context: BindingContext.PlanetDetail,
    longLabel: "BACK", shortLabel: "Back", priority: 90))

  # =========================================================================
  # Fleets Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Fleets,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Fleets,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Fleets,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Fleets,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.openFleetDetailModal,
    context: BindingContext.Fleets,
    longLabel: "DETAIL", shortLabel: "Enter", priority: 10,
    enabledCheck: "hasFleets"))

  registerBinding(Binding(
    key: KeyCode.KeyX, modifier: KeyModifier.None,
    actionKind: ActionKind.toggleFleetSelect,
    context: BindingContext.Fleets,
    longLabel: "SELECT", shortLabel: "Sel", priority: 15,
    enabledCheck: "hasFleets"))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.switchFleetView,
    context: BindingContext.Fleets,
    longLabel: "LIST/MAP", shortLabel: "L/M", priority: 20))
  
  # Fleet Console pane navigation (SystemView mode only)
  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsoleNextPane,
    context: BindingContext.Fleets,
    longLabel: "NEXT PANE", shortLabel: "→", priority: 21))
  
  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsolePrevPane,
    context: BindingContext.Fleets,
    longLabel: "PREV PANE", shortLabel: "←", priority: 22))
  
  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsoleNextPane,
    context: BindingContext.Fleets,
    longLabel: "NEXT PANE", shortLabel: "Tab", priority: 23))

  # =========================================================================
  # Fleet Detail Modal Context
  # =========================================================================

  # Main modal (subModal == None)
  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailConfirm,  # Opens command picker
    context: BindingContext.FleetDetail,
    longLabel: "COMMAND", shortLabel: "Cmd", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailOpenROE,
    context: BindingContext.FleetDetail,
    longLabel: "ROE", shortLabel: "ROE", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closeFleetDetailModal,
    context: BindingContext.FleetDetail,
    longLabel: "CLOSE", shortLabel: "Esc", priority: 90,
    enabledCheck: "noSubModal"))

  # Command Picker sub-modal
  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailNextCategory,
    context: BindingContext.FleetDetail,
    longLabel: "NEXT CAT", shortLabel: "Tab", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.Shift,
    actionKind: ActionKind.fleetDetailPrevCategory,
    context: BindingContext.FleetDetail,
    longLabel: "PREV CAT", shortLabel: "S-Tab", priority: 31))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListUp,
    context: BindingContext.FleetDetail,
    longLabel: "UP", shortLabel: "↑", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListDown,
    context: BindingContext.FleetDetail,
    longLabel: "DOWN", shortLabel: "↓", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailCancel,
    context: BindingContext.FleetDetail,
    longLabel: "CANCEL", shortLabel: "Esc", priority: 91))

  # ROE Picker sub-modal (shares bindings with command picker for navigation)
  # Up/Down keys already bound above
  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectROE,
    context: BindingContext.FleetDetail,
    longLabel: "CONFIRM ROE", shortLabel: "Enter", priority: 35))

  # Confirm dialog (Y/N)
  registerBinding(Binding(
    key: KeyCode.KeyY, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailConfirm,
    context: BindingContext.FleetDetail,
    longLabel: "YES", shortLabel: "Y", priority: 40))

  registerBinding(Binding(
    key: KeyCode.KeyN, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailCancel,
    context: BindingContext.FleetDetail,
    longLabel: "NO", shortLabel: "N", priority: 41))

  # =========================================================================
  # Research Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Research,
    longLabel: "ERP", shortLabel: "ERP", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyS, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Research,
    longLabel: "SRP", shortLabel: "SRP", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyT, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Research,
    longLabel: "TRP", shortLabel: "TRP", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Research,
    longLabel: "CONFIRM", shortLabel: "OK", priority: 40))

  # =========================================================================
  # Espionage Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Espionage,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Espionage,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyB, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Espionage,
    longLabel: "BUY EBP", shortLabel: "EBP", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Espionage,
    longLabel: "BUY CIP", shortLabel: "CIP", priority: 20))

  # =========================================================================
  # Economy Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Economy,
    longLabel: "TAX-", shortLabel: "-", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Economy,
    longLabel: "TAX+", shortLabel: "+", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Economy,
    longLabel: "CONFIRM", shortLabel: "OK", priority: 30))

  # =========================================================================
  # Reports Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Reports,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Reports,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Reports,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Reports,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Reports,
    longLabel: "VIEW", shortLabel: "View", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.reportFocusNext,
    context: BindingContext.Reports,
    longLabel: "FOCUS", shortLabel: "Foc", priority: 20))

  # =========================================================================
  # Report Detail Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.ReportDetail,
    longLabel: "JUMP", shortLabel: "Jump", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyN, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.ReportDetail,
    longLabel: "NEXT", shortLabel: "Next", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.breadcrumbBack,
    context: BindingContext.ReportDetail,
    longLabel: "BACK", shortLabel: "Back", priority: 90))

  # =========================================================================
  # Messages Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Messages,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Messages,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Messages,
    longLabel: "DIPLOMACY", shortLabel: "Dipl", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Messages,
    longLabel: "COMPOSE", shortLabel: "Comp", priority: 20))

  # =========================================================================
  # Settings Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Settings,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Settings,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Settings,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Settings,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Settings,
    longLabel: "CHANGE", shortLabel: "Chg", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Settings,
    longLabel: "RESET", shortLabel: "Rst", priority: 20))

  # =========================================================================
  # Build Modal Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategorySwitch,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY", shortLabel: "Cat", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListUp,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListDown,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "Nav", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.buildFocusSwitch,
    context: BindingContext.BuildModal,
    longLabel: "FOCUS", shortLabel: "Foc", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.buildFocusSwitch,
    context: BindingContext.BuildModal,
    longLabel: "FOCUS", shortLabel: "Foc", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.buildAddToQueue,
    context: BindingContext.BuildModal,
    longLabel: "ADD", shortLabel: "Add", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyX, modifier: KeyModifier.None,
    actionKind: ActionKind.buildRemoveFromQueue,
    context: BindingContext.BuildModal,
    longLabel: "REMOVE", shortLabel: "Rem", priority: 15))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.buildQuantityInc,
    context: BindingContext.BuildModal,
    longLabel: "QTY+", shortLabel: "+", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.buildQuantityDec,
    context: BindingContext.BuildModal,
    longLabel: "QTY-", shortLabel: "-", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyQ, modifier: KeyModifier.None,
    actionKind: ActionKind.buildConfirmQueue,
    context: BindingContext.BuildModal,
    longLabel: "CONFIRM", shortLabel: "OK", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closeBuildModal,
    context: BindingContext.BuildModal,
    longLabel: "CANCEL", shortLabel: "Esc", priority: 90))

  # =========================================================================
  # Order Entry Context (Target Selection)
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.moveCursor,
    context: BindingContext.OrderEntry,
    longLabel: "MOVE", shortLabel: "Mov", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.moveCursor,
    context: BindingContext.OrderEntry,
    longLabel: "MOVE", shortLabel: "Mov", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.moveCursor,
    context: BindingContext.OrderEntry,
    longLabel: "MOVE", shortLabel: "Mov", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.moveCursor,
    context: BindingContext.OrderEntry,
    longLabel: "MOVE", shortLabel: "Mov", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.confirmOrder,
    context: BindingContext.OrderEntry,
    longLabel: "CONFIRM", shortLabel: "OK", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.cancelOrder,
    context: BindingContext.OrderEntry,
    longLabel: "CANCEL", shortLabel: "Esc", priority: 90))

  # =========================================================================
  # Expert Mode Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.expertSubmit,
    context: BindingContext.ExpertMode,
    longLabel: "SUBMIT", shortLabel: "OK", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.exitExpertMode,
    context: BindingContext.ExpertMode,
    longLabel: "CANCEL", shortLabel: "Esc", priority: 90))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.expertHistoryPrev,
    context: BindingContext.ExpertMode,
    longLabel: "HISTORY", shortLabel: "Hist", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.expertHistoryNext,
    context: BindingContext.ExpertMode,
    longLabel: "HISTORY", shortLabel: "Hist", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyBackspace, modifier: KeyModifier.None,
    actionKind: ActionKind.expertInputBackspace,
    context: BindingContext.ExpertMode,
    longLabel: "DELETE", shortLabel: "Del", priority: 30))

# =============================================================================
# Action Dispatch
# =============================================================================

proc dispatchAction*(b: Binding, model: TuiModel,
    key: KeyCode): Option[Proposal] =
  ## Dispatch an action based on the binding's action name
  ## Some actions need parameters derived from key or model state

  case b.actionKind
  # View switching
  of ActionKind.switchView:
    let viewNum = case key
      of KeyCode.KeyO: 1
      of KeyCode.KeyC: 2
      of KeyCode.KeyF: 3
      of KeyCode.KeyT: 4
      of KeyCode.KeyE: 5
      of KeyCode.KeyG: 6
      of KeyCode.KeyR: 7
      of KeyCode.KeyI: 8
      of KeyCode.KeyS: 9
      else: 0
    if viewNum > 0:
      return some(actionSwitchView(viewNum))

  # Navigation
  of ActionKind.listUp:
    return some(actionListUp())
  of ActionKind.listDown:
    return some(actionListDown())
  of ActionKind.listPageUp:
    return some(actionListPageUp())
  of ActionKind.listPageDown:
    return some(actionListPageDown())
  of ActionKind.breadcrumbBack:
    return some(actionBreadcrumbBack())
  of ActionKind.navigateMode:
    return some(actionSwitchMode(ViewMode.Overview))

  # Cursor movement
  of ActionKind.moveCursor:
    let dir = case key
      of KeyCode.KeyUp: HexDirection.NorthWest
      of KeyCode.KeyDown: HexDirection.SouthEast
      of KeyCode.KeyLeft: HexDirection.West
      of KeyCode.KeyRight: HexDirection.East
      else: HexDirection.East
    return some(actionMoveCursor(dir))

  # Selection
  of ActionKind.select:
    return some(actionSelect())
  of ActionKind.deselect:
    return some(actionDeselect())
  of ActionKind.toggleFleetSelect:
    return some(actionToggleFleetSelect(model.ui.selectedIdx))

  # Expert mode
  of ActionKind.enterExpertMode:
    return some(actionEnterExpertMode())
  of ActionKind.exitExpertMode:
    return some(actionExitExpertMode())
  of ActionKind.expertSubmit:
    return some(actionExpertSubmit())
  of ActionKind.expertInputBackspace:
    return some(actionExpertInputBackspace())
  of ActionKind.expertHistoryPrev:
    return some(actionExpertHistoryPrev())
  of ActionKind.expertHistoryNext:
    return some(actionExpertHistoryNext())

  # Order entry
  of ActionKind.confirmOrder:
    return some(actionConfirmOrder(-1))  # -1 = use cursor
  of ActionKind.cancelOrder:
    return some(actionCancelOrder())
  of ActionKind.startOrderMove:
    if model.ui.selectedFleetId > 0:
      return some(actionStartOrderMove(model.ui.selectedFleetId))
  of ActionKind.startOrderPatrol:
    if model.ui.selectedFleetId > 0:
      return some(actionStartOrderPatrol(model.ui.selectedFleetId))
  of ActionKind.startOrderHold:
    if model.ui.selectedFleetId > 0:
      return some(actionStartOrderHold(model.ui.selectedFleetId))

  # Quit
  of ActionKind.quit:
    return some(actionQuit())
  of ActionKind.quitConfirm:
    return some(actionQuitConfirm())
  of ActionKind.quitCancel:
    return some(actionQuitCancel())

  # Turn submission
  of ActionKind.submitTurn:
    return some(actionSubmitTurn())

  # View-specific tabs
  of ActionKind.switchPlanetTab:
    let tab = case key
      of KeyCode.Key1: 1
      of KeyCode.Key2: 2
      of KeyCode.Key3: 3
      of KeyCode.Key4: 4
      of KeyCode.Key5: 5
      of KeyCode.KeyLeft: -1  # Previous tab
      of KeyCode.KeyRight: 1  # Next tab
      of KeyCode.KeyTab: 1  # Next tab
      of KeyCode.KeyS: 1  # Summary
      of KeyCode.KeyE: 2  # Economy
      of KeyCode.KeyC: 3  # Construction
      of KeyCode.KeyD: 4  # Defense
      of KeyCode.KeyG: 5  # Settings (confiG)
      else: 0
    if tab != 0:
      return some(actionSwitchPlanetTab(tab))
  of ActionKind.switchFleetView:
    return some(actionSwitchFleetView())
  of ActionKind.cycleReportFilter:
    return some(actionCycleReportFilter())
  of ActionKind.reportFocusNext:
    return some(actionReportFocusNext())
  of ActionKind.reportFocusPrev:
    return some(actionReportFocusPrev())
  of ActionKind.reportFocusLeft:
    return some(actionReportFocusLeft())
  of ActionKind.reportFocusRight:
    return some(actionReportFocusRight())

  # Lobby actions (handled separately in mapKeyToAction)
  of ActionKind.lobbyReturn:
    return some(actionLobbyReturn())

  # Build modal actions
  of ActionKind.openBuildModal:
    # Will be handled in acceptor to get colony ID
    return some(actionOpenBuildModal(0))
  of ActionKind.closeBuildModal:
    return some(actionCloseBuildModal())
  of ActionKind.buildCategorySwitch:
    return some(actionBuildCategorySwitch())
  of ActionKind.buildListUp:
    return some(actionBuildListUp())
  of ActionKind.buildListDown:
    return some(actionBuildListDown())
  of ActionKind.buildQueueUp:
    return some(actionBuildQueueUp())
  of ActionKind.buildQueueDown:
    return some(actionBuildQueueDown())
  of ActionKind.buildFocusSwitch:
    return some(actionBuildFocusSwitch())
  of ActionKind.buildAddToQueue:
    return some(actionBuildAddToQueue())
  of ActionKind.buildRemoveFromQueue:
    return some(actionBuildRemoveFromQueue())
  of ActionKind.buildConfirmQueue:
    return some(actionBuildConfirmQueue())
  of ActionKind.buildQuantityInc:
    return some(actionBuildQuantityInc())
  of ActionKind.buildQuantityDec:
    return some(actionBuildQuantityDec())
  
  # Fleet console pane navigation
  of ActionKind.fleetConsoleNextPane:
    return some(actionFleetConsoleNextPane())
  of ActionKind.fleetConsolePrevPane:
    return some(actionFleetConsolePrevPane())

  # Fleet detail modal actions
  of ActionKind.openFleetDetailModal:
    return some(actionOpenFleetDetailModal())
  of ActionKind.closeFleetDetailModal:
    return some(actionCloseFleetDetailModal())
  of ActionKind.fleetDetailNextCategory:
    return some(actionFleetDetailNextCategory())
  of ActionKind.fleetDetailPrevCategory:
    return some(actionFleetDetailPrevCategory())
  of ActionKind.fleetDetailListUp:
    return some(actionFleetDetailListUp())
  of ActionKind.fleetDetailListDown:
    return some(actionFleetDetailListDown())
  of ActionKind.fleetDetailSelectCommand:
    return some(actionFleetDetailSelectCommand())
  of ActionKind.fleetDetailOpenROE:
    return some(actionFleetDetailOpenROE())
  of ActionKind.fleetDetailCloseROE:
    return some(actionFleetDetailCloseROE())
  of ActionKind.fleetDetailROEUp:
    return some(actionFleetDetailROEUp())
  of ActionKind.fleetDetailROEDown:
    return some(actionFleetDetailROEDown())
  of ActionKind.fleetDetailSelectROE:
    return some(actionFleetDetailSelectROE())
  of ActionKind.fleetDetailConfirm:
    return some(actionFleetDetailConfirm())
  of ActionKind.fleetDetailCancel:
    return some(actionFleetDetailCancel())

  else:
    discard

  none(Proposal)

proc lookupAndDispatch*(key: KeyCode, modifier: KeyModifier,
    ctx: BindingContext, model: TuiModel): Option[Proposal] =
  ## Look up a binding and dispatch the action if found
  let binding = findBinding(key, modifier, ctx, model)
  if binding.isSome:
    let b = binding.get()
    # Note: isBindingEnabled already called in findBinding
    return dispatchAction(b, model, key)
  none(Proposal)

proc lookupGlobalAndDispatch*(key: KeyCode, modifier: KeyModifier,
    model: TuiModel): Option[Proposal] =
  ## Look up a global binding and dispatch the action if found
  lookupAndDispatch(key, modifier, BindingContext.Global, model)

# =============================================================================
# Key Mapping (Single Source of Truth)
# =============================================================================

proc mapKeyToAction*(key: KeyCode, modifier: KeyModifier,
    model: TuiModel): Option[Proposal] =
  ## Map a key code to an action based on current model state
  ## Uses the binding registry as the single source of truth for key mappings.
  ## Returns None if no action should be taken.
  ##
  ## Special modes (quit confirmation, lobby text input) are handled separately
  ## since they don't fit the registry pattern well.

  # Alt+Q or Ctrl+Q always quits (global)
  if key == KeyCode.KeyQ and modifier == KeyModifier.Alt:
    return some(actionQuit())
  if key == KeyCode.KeyCtrlQ:
    return some(actionQuit())

  # Quit confirmation modal - takes precedence over everything
  if model.ui.quitConfirmationActive:
    case key
    of KeyCode.KeyY:
      return some(actionQuitConfirm())
    of KeyCode.KeyN, KeyCode.KeyEscape:
      return some(actionQuitCancel())
    of KeyCode.KeyLeft, KeyCode.KeyRight:
      return some(actionQuitToggle())
    of KeyCode.KeyH, KeyCode.KeyL:
      return some(actionQuitToggle())
    of KeyCode.KeyEnter:
      if model.ui.quitConfirmationChoice == QuitConfirmationChoice.QuitExit:
        return some(actionQuitConfirm())
      return some(actionQuitCancel())
    else:
      return none(Proposal)

  # Build modal mode: use registry
  if model.ui.buildModal.active and modifier == KeyModifier.None:
    let buildResult = lookupAndDispatch(key, KeyModifier.None,
        BindingContext.BuildModal, model)
    if buildResult.isSome:
      return buildResult
    return none(Proposal)

  # Fleet detail view mode: use registry
  if model.ui.mode == ViewMode.FleetDetail:
    let fleetDetailResult = lookupAndDispatch(key, modifier,
        BindingContext.FleetDetail, model)
    if fleetDetailResult.isSome:
      return fleetDetailResult
    # Allow global bindings (Alt+key) to pass through, block other keys
    if modifier != KeyModifier.Alt:
      return none(Proposal)

  # Order entry mode: use registry
  if model.ui.orderEntryActive and modifier == KeyModifier.None:
    let orderResult = lookupAndDispatch(key, KeyModifier.None,
        BindingContext.OrderEntry, model)
    if orderResult.isSome:
      return orderResult
    # Q also cancels (not in registry for cleanliness)
    if key == KeyCode.KeyQ:
      return some(actionCancelOrder())
    return none(Proposal)

  # Expert mode: use registry
  if model.ui.expertModeActive and modifier == KeyModifier.None:
    let expertResult = lookupAndDispatch(key, KeyModifier.None,
        BindingContext.ExpertMode, model)
    if expertResult.isSome:
      return expertResult
    # Other keys add to input buffer - handled by acceptor
    return none(Proposal)

  # Lobby phase: special handling for text input modes
  if model.ui.appPhase == AppPhase.Lobby:
    if model.ui.entryModal.mode == EntryModalMode.ImportNsec:
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryImportConfirm())
      of KeyCode.KeyEscape:
        return some(actionEntryImportCancel())
      of KeyCode.KeyBackspace:
        return some(actionEntryImportBackspace())
      else:
        if modifier != KeyModifier.Alt:
          return none(Proposal)

    elif model.ui.entryModal.editingRelay:
      case key
      of KeyCode.KeyEnter, KeyCode.KeyEscape:
        return some(actionEntryRelayConfirm())
      of KeyCode.KeyBackspace:
        return some(actionEntryRelayBackspace())
      else:
        if modifier != KeyModifier.Alt:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.CreateGame:
      case key
      of KeyCode.KeyEscape:
        return some(actionCreateGameCancel())
      of KeyCode.KeyUp:
        return some(actionCreateGameUp())
      of KeyCode.KeyDown:
        return some(actionCreateGameDown())
      of KeyCode.KeyLeft:
        return some(actionCreateGameLeft())
      of KeyCode.KeyRight:
        return some(actionCreateGameRight())
      of KeyCode.KeyEnter:
        return some(actionCreateGameConfirm())
      of KeyCode.KeyBackspace:
        return some(actionCreateGameBackspace())
      else:
        if modifier != KeyModifier.Alt:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.ManageGames:
      case key
      of KeyCode.KeyEscape:
        return some(actionManageGamesCancel())
      else:
        if modifier != KeyModifier.Alt:
          return none(Proposal)

    else:
      # Normal entry modal mode
      case key
      of KeyCode.KeyUp:
        return some(actionEntryUp())
      of KeyCode.KeyDown:
        return some(actionEntryDown())
      of KeyCode.KeyEnter:
        case model.ui.entryModal.focus
        of EntryModalFocus.InviteCode:
          return some(actionEntryInviteSubmit())
        of EntryModalFocus.AdminMenu:
          return some(actionEntryAdminSelect())
        of EntryModalFocus.GameList:
          return some(actionEntrySelect())
        of EntryModalFocus.RelayUrl:
          return some(actionEntryRelayEdit())
      of KeyCode.KeyBackspace:
        if model.ui.entryModal.focus == EntryModalFocus.InviteCode:
          return some(actionEntryInviteBackspace())
        elif model.ui.entryModal.focus == EntryModalFocus.RelayUrl:
          return some(actionEntryRelayBackspace())
        else:
          return none(Proposal)
      of KeyCode.KeyI:
        return some(actionEntryImport())
      else:
        if modifier != KeyModifier.Alt:
          return none(Proposal)

  # In-game Ctrl+L returns to lobby
  if model.ui.appPhase == AppPhase.InGame:
    if key == KeyCode.KeyCtrlL:
      return some(actionLobbyReturn())

  # Global bindings (view switching, expert mode, etc.)
  let globalResult = lookupGlobalAndDispatch(key, modifier, model)
  if globalResult.isSome:
    return globalResult

  # Context-specific bindings based on current view mode
  if modifier == KeyModifier.None:
    let ctx = viewModeToContext(model.ui.mode)
    let ctxResult = lookupAndDispatch(key, KeyModifier.None, ctx, model)
    if ctxResult.isSome:
      return ctxResult

  none(Proposal)

# =============================================================================
# Bar Item Building
# =============================================================================

proc buildBarItems*(model: TuiModel, useShortLabels: bool): seq[BarItem] =
  ## Build bar items based on current model state
  ## If in Overview, show global view tabs
  ## Otherwise, show context-specific actions

  result = @[]

  # Determine which bindings to show
  let showGlobalTabs = model.ui.appPhase == AppPhase.InGame and
      model.ui.mode == ViewMode.Overview and
      not model.ui.expertModeActive and
      not model.ui.orderEntryActive

  if showGlobalTabs:
    # Show view tabs (Alt+Key) + expert mode hint
    let globalBindings = getGlobalBindings()
    var idx = 0
    for b in globalBindings:
      # Skip quit in normal tab display (it's always Alt+Q)
      if b.actionKind == ActionKind.quit:
        continue

      let label = if useShortLabels: b.shortLabel else: b.longLabel
      let isSelected = case b.key
        of KeyCode.KeyO: model.ui.mode == ViewMode.Overview
        of KeyCode.KeyC: model.ui.mode == ViewMode.Planets
        of KeyCode.KeyF: model.ui.mode == ViewMode.Fleets
        of KeyCode.KeyT: model.ui.mode == ViewMode.Research
        of KeyCode.KeyE: model.ui.mode == ViewMode.Espionage
        of KeyCode.KeyG: model.ui.mode == ViewMode.Economy
        of KeyCode.KeyR: model.ui.mode == ViewMode.Reports
        of KeyCode.KeyI: model.ui.mode == ViewMode.Messages
        of KeyCode.KeyS: model.ui.mode == ViewMode.Settings
        else: false

      let mode = if isSelected: BarItemMode.Selected
                 elif idx mod 2 == 1: BarItemMode.UnselectedAlt
                 else: BarItemMode.Unselected

      result.add(BarItem(
        keyDisplay: formatKey(b.key, b.modifier),
        label: label,
        longLabel: b.longLabel,
        shortLabel: b.shortLabel,
        mode: mode,
        binding: b
      ))
      idx.inc
  else:
    # Show context-specific actions
    let ctx = if model.ui.expertModeActive: BindingContext.ExpertMode
              elif model.ui.orderEntryActive: BindingContext.OrderEntry
              else: viewModeToContext(model.ui.mode)

    let bindings = getBindingsForContext(ctx)

    # Group arrow keys together as ↑↓ or ←→
    var seenNavUp = false
    var seenNavLeft = false

    var idx = 0
    for b in bindings:
      # Skip duplicate nav keys - combine ↑↓ and ←→
      if b.key == KeyCode.KeyDown and seenNavUp:
        continue
      if b.key == KeyCode.KeyRight and seenNavLeft:
        continue
      if b.key == KeyCode.KeyUp:
        seenNavUp = true
      if b.key == KeyCode.KeyLeft:
        seenNavLeft = true

      let enabled = isBindingEnabled(b, model)
      let label = if useShortLabels: b.shortLabel else: b.longLabel

      # Format key display - combine arrows if nav
      let keyDisp = if b.key == KeyCode.KeyUp: "↑↓"
                    elif b.key == KeyCode.KeyLeft: "←→"
                    else: formatKey(b.key, b.modifier)

      let mode = if not enabled: BarItemMode.Disabled
                 elif idx mod 2 == 1: BarItemMode.UnselectedAlt
                 else: BarItemMode.Unselected

      result.add(BarItem(
        keyDisplay: keyDisp,
        label: label,
        longLabel: b.longLabel,
        shortLabel: b.shortLabel,
        mode: mode,
        binding: b
      ))
      idx.inc
