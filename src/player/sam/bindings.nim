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

import std/[algorithm, options, sequtils, strutils]
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
 
# View switching hotkeys use Ctrl across platforms
const ViewModifier* = KeyModifier.Ctrl

type
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
    IntelDb       ## Intel database list
    IntelDetail   ## Intel system detail
    Messages      ## Messages view
    Lobby         ## Entry screen / lobby
    ExpertMode    ## Expert command mode
    BuildModal    ## Build command modal
    QueueModal    ## Queue modal
    PopulationTransferModal ## Population transfer staging modal

  Binding* = object
    key*: actions.KeyCode
    modifier*: KeyModifier
    actionKind*: ActionKind   ## Enum-based action identifier
    longLabel*: string        ## Full label: "VIEW COLONY"
    shortLabel*: string       ## Short label: "VIEW"
    context*: BindingContext
    priority*: int            ## Display order (lower = first)
    enabledCheck*: string     ## Name of condition check (empty = always)
    hidden*: bool             ## Hide from UI (still active)

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
    labelBefore*: string      ## Label text before key bracket
    labelAfter*: string       ## Label text after key bracket
    labelHasPipe*: bool       ## Label uses pipe split for key placement
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
    priority: int = 0, enabledCheck: string = "", hidden: bool = false) =
  ## Register a new binding using enum actionKind (new signature)
  gBindings.add(Binding(
    key: key,
    modifier: modifier,
    actionKind: actionKind,
    longLabel: longLabel,
    shortLabel: shortLabel,
    context: context,
    priority: priority,
    enabledCheck: enabledCheck,
    hidden: hidden
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
  of actions.KeyCode.Key0: "0"
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
  of actions.KeyCode.KeyK: "k"
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
  of actions.KeyCode.KeyZ: "z"
  of actions.KeyCode.KeyPlus: "+"
  of actions.KeyCode.KeyMinus: "-"
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
  of actions.KeyCode.KeyDelete: "Del"
  of actions.KeyCode.KeyPageUp: "PgUp"
  of actions.KeyCode.KeyPageDown: "PgDn"
  of actions.KeyCode.KeyF1: "F1"
  of actions.KeyCode.KeyF2: "F2"
  of actions.KeyCode.KeyF3: "F3"
  of actions.KeyCode.KeyF4: "F4"
  of actions.KeyCode.KeyF5: "F5"
  of actions.KeyCode.KeyF6: "F6"
  of actions.KeyCode.KeyF7: "F7"
  of actions.KeyCode.KeyF8: "F8"
  of actions.KeyCode.KeyF9: "F9"
  of actions.KeyCode.KeyF10: "F10"
  of actions.KeyCode.KeyF11: "F11"
  of actions.KeyCode.KeyF12: "F12"
  of actions.KeyCode.KeyColon: ":"
  of actions.KeyCode.KeySlash: "/"
  of actions.KeyCode.KeyCtrlL: "Ctrl-L"
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

proc getViewModifierPrefix*(): string =
  ## Get the modifier prefix for status bar display
  ""

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
  of ViewMode.IntelDb: BindingContext.IntelDb
  of ViewMode.IntelDetail: BindingContext.IntelDetail
  of ViewMode.Messages: BindingContext.Messages
  of ViewMode.PlanetDetail: BindingContext.PlanetDetail
  of ViewMode.FleetDetail: BindingContext.FleetDetail

proc contextToViewMode*(ctx: BindingContext): Option[ViewMode] =
  ## Map a binding context to ViewMode (if applicable)
  case ctx
  of BindingContext.Overview: some(ViewMode.Overview)
  of BindingContext.Planets: some(ViewMode.Planets)
  of BindingContext.Fleets: some(ViewMode.Fleets)
  of BindingContext.Research: some(ViewMode.Research)
  of BindingContext.Espionage: some(ViewMode.Espionage)
  of BindingContext.Economy: some(ViewMode.Economy)
  of BindingContext.IntelDb: some(ViewMode.IntelDb)
  of BindingContext.IntelDetail: some(ViewMode.IntelDetail)
  of BindingContext.Messages: some(ViewMode.Messages)
  of BindingContext.PlanetDetail: some(ViewMode.PlanetDetail)
  of BindingContext.FleetDetail: some(ViewMode.FleetDetail)
  of BindingContext.QueueModal: none(ViewMode)
  of BindingContext.PopulationTransferModal: none(ViewMode)
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
  of "hasSubModal":
    model.ui.fleetDetailModal.subModal != FleetSubModal.None
  of "isCommandPicker":
    model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker
  of "isROEPicker":
    model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker
  of "isZTCPicker":
    model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker
  of "isFleetPicker":
    model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker
  of "isSystemPicker":
    model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker
  of "isShipSelector":
    model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector
  of "isNoticePrompt":
    model.ui.fleetDetailModal.subModal == FleetSubModal.NoticePrompt
  of "isEspionageBudgetFocus":
    model.ui.mode == ViewMode.Espionage and
      model.ui.espionageFocus == EspionageFocus.Budget
  of "isEspionageNonBudgetFocus":
    model.ui.mode == ViewMode.Espionage and
      model.ui.espionageFocus != EspionageFocus.Budget
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
  # Ctrl+Letter across all platforms
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyO, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|verview", shortLabel: "|vr", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyN, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "i|box", shortLabel: "i|b", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyG, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|eneral", shortLabel: "|en", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyY, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "colon|", shortLabel: "cl|", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyF, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|leet", shortLabel: "|lt", priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyT, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|ech", shortLabel: "|ch", priority: 7))

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|spionage", shortLabel: "|sp", priority: 8))

  registerBinding(Binding(
    key: KeyCode.KeyI, modifier: ViewModifier,
    actionKind: ActionKind.switchView,
    context: BindingContext.Global,
    longLabel: "|ntel", shortLabel: "|nt", priority: 9))

  registerBinding(Binding(
    key: KeyCode.KeyX, modifier: ViewModifier,
    actionKind: ActionKind.quit,
    context: BindingContext.Global,
    longLabel: "e|it", shortLabel: "e|", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeySlash, modifier: KeyModifier.Ctrl,
    actionKind: ActionKind.toggleHelpOverlay,
    context: BindingContext.Global,
    longLabel: "help", shortLabel: "", priority: 12))

  registerBinding(Binding(
    key: KeyCode.KeyColon, modifier: KeyModifier.None,
    actionKind: ActionKind.enterExpertMode,
    context: BindingContext.Global,
    longLabel: "expert", shortLabel: "", priority: 100))

  registerBinding(Binding(
    key: KeyCode.KeyU, modifier: KeyModifier.Ctrl,
    actionKind: ActionKind.submitTurn,
    context: BindingContext.Global,
    longLabel: "s|bmit", shortLabel: "s|b", priority: 99))

  registerBinding(Binding(
    key: KeyCode.KeyF5, modifier: KeyModifier.None,
    actionKind: ActionKind.submitTurn,
    context: BindingContext.Global,
    longLabel: "SUBMIT", shortLabel: "GO", priority: 99,
    hidden: true))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.Ctrl,
    actionKind: ActionKind.submitTurn,
    context: BindingContext.Global,
    longLabel: "SUBMIT", shortLabel: "GO", priority: 99,
    hidden: true))



  # =========================================================================
  # Overview Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Overview,
    longLabel: "NAV", shortLabel: "J", priority: 2))

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
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Planets,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Planets,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Planets,
    longLabel: "NAV", shortLabel: "J", priority: 2))

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
    actionKind: ActionKind.openBuildModal,
    context: BindingContext.Planets,
    longLabel: "BUILD", shortLabel: "Bld", priority: 20,
    enabledCheck: "hasColonySelection"))

  registerBinding(Binding(
    key: KeyCode.KeyQ, modifier: KeyModifier.None,
    actionKind: ActionKind.openQueueModal,
    context: BindingContext.Planets,
    longLabel: "QUEUE", shortLabel: "Que", priority: 21,
    enabledCheck: "hasColonySelection"))

  registerBinding(Binding(
    key: KeyCode.KeyT, modifier: KeyModifier.None,
    actionKind: ActionKind.openPopulationTransferModal,
    context: BindingContext.Planets,
    longLabel: "TRANSFER", shortLabel: "Xfer", priority: 22,
    enabledCheck: "hasColonySelection"))

  registerBinding(Binding(
    key: KeyCode.KeyV, modifier: KeyModifier.None,
    actionKind: ActionKind.stageTerraformCommand,
    context: BindingContext.Planets,
    longLabel: "TERRAFORM", shortLabel: "Ter", priority: 23,
    enabledCheck: "hasColonySelection"))

  # =========================================================================
  # Planet Detail Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.cycleColony,
    context: BindingContext.PlanetDetail,
    longLabel: "PREV COL", shortLabel: "←", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.cycleColony,
    context: BindingContext.PlanetDetail,
    longLabel: "PREV COL", shortLabel: "H", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.cycleColony,
    context: BindingContext.PlanetDetail,
    longLabel: "NEXT COL", shortLabel: "→", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.cycleColony,
    context: BindingContext.PlanetDetail,
    longLabel: "NEXT COL", shortLabel: "L", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.cycleColony,
    context: BindingContext.PlanetDetail,
    longLabel: "NEXT COL", shortLabel: "Tab", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyB, modifier: KeyModifier.None,
    actionKind: ActionKind.openBuildModal,
    context: BindingContext.PlanetDetail,
    longLabel: "BUILD", shortLabel: "Bld", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyQ, modifier: KeyModifier.None,
    actionKind: ActionKind.openQueueModal,
    context: BindingContext.PlanetDetail,
    longLabel: "QUEUE", shortLabel: "Que", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.toggleAutoRepair,
    context: BindingContext.PlanetDetail,
    longLabel: "AUTO REPAIR", shortLabel: "Repair", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyM, modifier: KeyModifier.None,
    actionKind: ActionKind.toggleAutoLoadMarines,
    context: BindingContext.PlanetDetail,
    longLabel: "AUTO MARINES", shortLabel: "Marines", priority: 31))

  registerBinding(Binding(
    key: KeyCode.KeyF, modifier: KeyModifier.None,
    actionKind: ActionKind.toggleAutoLoadFighters,
    context: BindingContext.PlanetDetail,
    longLabel: "AUTO FIGHTERS", shortLabel: "Fighters", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyT, modifier: KeyModifier.None,
    actionKind: ActionKind.openPopulationTransferModal,
    context: BindingContext.PlanetDetail,
    longLabel: "TRANSFER", shortLabel: "Xfer", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyV, modifier: KeyModifier.None,
    actionKind: ActionKind.stageTerraformCommand,
    context: BindingContext.PlanetDetail,
    longLabel: "TERRAFORM", shortLabel: "Ter", priority: 34))

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
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Fleets,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Fleets,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Fleets,
    longLabel: "NAV", shortLabel: "J", priority: 2))

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
    key: KeyCode.KeyV, modifier: KeyModifier.None,
    actionKind: ActionKind.switchFleetView,
    context: BindingContext.Fleets,
    longLabel: "LIST/MAP", shortLabel: "L/M", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyS, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetSortToggle,
    context: BindingContext.Fleets,
    longLabel: "ASC/DESC", shortLabel: "A/D",
    priority: 24,
    enabledCheck: "hasFleets"))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetBatchCommand,
    context: BindingContext.Fleets,
    longLabel: "CMD", shortLabel: "Cmd", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetBatchROE,
    context: BindingContext.Fleets,
    longLabel: "ROE", shortLabel: "ROE", priority: 31))

  registerBinding(Binding(
    key: KeyCode.KeyZ, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetBatchZeroTurn,
    context: BindingContext.Fleets,
    longLabel: "ZTC", shortLabel: "ZTC", priority: 32))

  
  # Fleet Console pane navigation (SystemView mode only)
  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsoleNextPane,
    context: BindingContext.Fleets,
    longLabel: "NEXT PANE", shortLabel: "→", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsoleNextPane,
    context: BindingContext.Fleets,
    longLabel: "NEXT PANE", shortLabel: "L", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsolePrevPane,
    context: BindingContext.Fleets,
    longLabel: "PREV PANE", shortLabel: "←", priority: 22))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetConsolePrevPane,
    context: BindingContext.Fleets,
    longLabel: "PREV PANE", shortLabel: "H", priority: 22))

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
    key: KeyCode.KeyZ, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailOpenZTC,
    context: BindingContext.FleetDetail,
    longLabel: "ZTC", shortLabel: "ZTC", priority: 25))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closeFleetDetailModal,
    context: BindingContext.FleetDetail,
    longLabel: "CLOSE", shortLabel: "Esc", priority: 90,
    enabledCheck: "noSubModal"))

  # Command Picker sub-modal - navigates flat list of 20 commands
  # Digit keys (0-9) handled specially in bindings for quick entry

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListUp,
    context: BindingContext.FleetDetail,
    longLabel: "UP", shortLabel: "↑", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListUp,
    context: BindingContext.FleetDetail,
    longLabel: "UP", shortLabel: "K", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListDown,
    context: BindingContext.FleetDetail,
    longLabel: "DOWN", shortLabel: "↓", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListDown,
    context: BindingContext.FleetDetail,
    longLabel: "DOWN", shortLabel: "J", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34,
    enabledCheck: "isCommandPicker"))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34,
    enabledCheck: "isFleetPicker"))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34,
    enabledCheck: "isSystemPicker"))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34,
    enabledCheck: "isShipSelector"))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectCommand,
    context: BindingContext.FleetDetail,
    longLabel: "SELECT", shortLabel: "Enter", priority: 34,
    enabledCheck: "isZTCPicker"))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailCancel,
    context: BindingContext.FleetDetail,
    longLabel: "BACK", shortLabel: "Enter", priority: 34,
    enabledCheck: "isNoticePrompt"))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListUp,
    context: BindingContext.FleetDetail,
    longLabel: "UP", shortLabel: "←", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListDown,
    context: BindingContext.FleetDetail,
    longLabel: "DOWN", shortLabel: "→", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListUp,
    context: BindingContext.FleetDetail,
    longLabel: "UP", shortLabel: "H", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailListDown,
    context: BindingContext.FleetDetail,
    longLabel: "DOWN", shortLabel: "L", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailCancel,
    context: BindingContext.FleetDetail,
    longLabel: "CANCEL", shortLabel: "Esc", priority: 91,
    enabledCheck: "hasSubModal"))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailPageUp,
    context: BindingContext.FleetDetail,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 50))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailPageDown,
    context: BindingContext.FleetDetail,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 51))

  # ROE Picker sub-modal (shares bindings with command picker for navigation)
  # Up/Down keys already bound above
  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.fleetDetailSelectROE,
    context: BindingContext.FleetDetail,
    longLabel: "CONFIRM ROE", shortLabel: "Enter", priority: 35,
    enabledCheck: "isROEPicker"))

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
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Research,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Research,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Research,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Research,
    longLabel: "NAV", shortLabel: "J", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Research,
    longLabel: "PGUP", shortLabel: "PgU", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Research,
    longLabel: "PGDN", shortLabel: "PgD", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.None,
    actionKind: ActionKind.researchAdjustInc,
    context: BindingContext.Research,
    longLabel: "+", shortLabel: "+", priority: 40))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.None,
    actionKind: ActionKind.researchAdjustDec,
    context: BindingContext.Research,
    longLabel: "-", shortLabel: "-", priority: 41))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.Shift,
    actionKind: ActionKind.researchAdjustFineInc,
    context: BindingContext.Research,
    longLabel: "+1", shortLabel: "+1", priority: 42))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.Shift,
    actionKind: ActionKind.researchAdjustFineDec,
    context: BindingContext.Research,
    longLabel: "-1", shortLabel: "-1", priority: 43))

  registerBinding(Binding(
    key: KeyCode.Key0, modifier: KeyModifier.None,
    actionKind: ActionKind.researchClearAllocation,
    context: BindingContext.Research,
    longLabel: "CLEAR", shortLabel: "0", priority: 44))

  # =========================================================================
  # Espionage Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageFocusNext,
    context: BindingContext.Espionage,
    longLabel: "NEXT PANEL", shortLabel: "Tab", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyShiftTab, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageFocusPrev,
    context: BindingContext.Espionage,
    longLabel: "PREV PANEL", shortLabel: "S-Tab", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageSelectEbp,
    context: BindingContext.Espionage,
    longLabel: "SELECT EBP", shortLabel: "←", priority: 3,
    enabledCheck: "isEspionageBudgetFocus"))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageFocusPrev,
    context: BindingContext.Espionage,
    longLabel: "PREV PANEL", shortLabel: "←", priority: 4,
    enabledCheck: "isEspionageNonBudgetFocus"))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageSelectCip,
    context: BindingContext.Espionage,
    longLabel: "SELECT CIP", shortLabel: "→", priority: 5,
    enabledCheck: "isEspionageBudgetFocus"))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageFocusNext,
    context: BindingContext.Espionage,
    longLabel: "NEXT PANEL", shortLabel: "→", priority: 6,
    enabledCheck: "isEspionageNonBudgetFocus"))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "Nav", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "K", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "Nav", priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Espionage,
    longLabel: "NAV", shortLabel: "J", priority: 7))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.Espionage,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 8))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.Espionage,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 9))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageBudgetAdjustInc,
    context: BindingContext.Espionage,
    longLabel: "BUDGET+", shortLabel: "+", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageBudgetAdjustDec,
    context: BindingContext.Espionage,
    longLabel: "BUDGET-", shortLabel: "-", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageQueueAdd,
    context: BindingContext.Espionage,
    longLabel: "QUEUE", shortLabel: "Enter", priority: 12))

  registerBinding(Binding(
    key: KeyCode.KeyB, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageSelectEbp,
    context: BindingContext.Espionage,
    longLabel: "SELECT EBP", shortLabel: "EBP", priority: 13))

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageSelectEbp,
    context: BindingContext.Espionage,
    longLabel: "SELECT EBP", shortLabel: "EBP", priority: 14))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageSelectCip,
    context: BindingContext.Espionage,
    longLabel: "SELECT CIP", shortLabel: "CIP", priority: 15))

  registerBinding(Binding(
    key: KeyCode.Key0, modifier: KeyModifier.None,
    actionKind: ActionKind.espionageClearBudget,
    context: BindingContext.Espionage,
    longLabel: "CLEAR BUDGET", shortLabel: "0", priority: 16))

  # =========================================================================
  # Economy Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.economyFocusNext,
    context: BindingContext.Economy,
    longLabel: "NEXT PANEL", shortLabel: "Tab", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.economyFocusPrev,
    context: BindingContext.Economy,
    longLabel: "PREV PANEL", shortLabel: "↑", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Economy,
    longLabel: "NAV", shortLabel: "K", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.economyFocusNext,
    context: BindingContext.Economy,
    longLabel: "NEXT PANEL", shortLabel: "↓", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Economy,
    longLabel: "NAV", shortLabel: "J", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxDec,
    context: BindingContext.Economy,
    longLabel: "TAX-", shortLabel: "◀", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxDec,
    context: BindingContext.Economy,
    longLabel: "TAX-", shortLabel: "H", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxInc,
    context: BindingContext.Economy,
    longLabel: "TAX+", shortLabel: "▶", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxInc,
    context: BindingContext.Economy,
    longLabel: "TAX+", shortLabel: "L", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxFineDec,
    context: BindingContext.Economy,
    longLabel: "TAX-1%", shortLabel: "-", priority: 12))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.None,
    actionKind: ActionKind.economyTaxFineInc,
    context: BindingContext.Economy,
    longLabel: "TAX+1%", shortLabel: "+", priority: 22))

  registerBinding(Binding(
    key: KeyCode.KeyE, modifier: KeyModifier.None,
    actionKind: ActionKind.economyDiplomacyAction,
    context: BindingContext.Economy,
    longLabel: "ESCALATE", shortLabel: "E", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyP, modifier: KeyModifier.None,
    actionKind: ActionKind.economyDiplomacyPropose,
    context: BindingContext.Economy,
    longLabel: "PROPOSE", shortLabel: "P", priority: 31))

  registerBinding(Binding(
    key: KeyCode.KeyA, modifier: KeyModifier.None,
    actionKind: ActionKind.economyDiplomacyAccept,
    context: BindingContext.Economy,
    longLabel: "ACCEPT", shortLabel: "A", priority: 32))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.economyDiplomacyReject,
    context: BindingContext.Economy,
    longLabel: "REJECT", shortLabel: "R", priority: 33))

  registerBinding(Binding(
    key: KeyCode.KeyM, modifier: KeyModifier.None,
    actionKind: ActionKind.exportMap,
    context: BindingContext.Economy,
    longLabel: "EXPORT MAP", shortLabel: "M", priority: 40))

  # =========================================================================
  # Intel DB Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.IntelDb,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.IntelDb,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.IntelDb,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.IntelDb,
    longLabel: "NAV", shortLabel: "J", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.IntelDb,
    longLabel: "PAGE UP", shortLabel: "PgUp", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.IntelDb,
    longLabel: "PAGE DOWN", shortLabel: "PgDn", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.IntelDb,
    longLabel: "DETAIL", shortLabel: "Dtl", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyN, modifier: KeyModifier.None,
    actionKind: ActionKind.intelEditNote,
    context: BindingContext.IntelDb,
    longLabel: "NOTE", shortLabel: "Note", priority: 20))

  # =========================================================================
  # Intel Detail Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyN, modifier: KeyModifier.None,
    actionKind: ActionKind.intelEditNote,
    context: BindingContext.IntelDetail,
    longLabel: "NOTE", shortLabel: "Note", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.IntelDetail,
    longLabel: "DETAIL", shortLabel: "Dtl", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.IntelDetail,
    longLabel: "FLEET UP", shortLabel: "↑", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.IntelDetail,
    longLabel: "FLEET UP", shortLabel: "K", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.IntelDetail,
    longLabel: "FLEET DOWN", shortLabel: "↓", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.IntelDetail,
    longLabel: "FLEET DOWN", shortLabel: "J", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageUp,
    context: BindingContext.IntelDetail,
    longLabel: "NOTES UP", shortLabel: "PgUp", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listPageDown,
    context: BindingContext.IntelDetail,
    longLabel: "NOTES DOWN", shortLabel: "PgDn", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.breadcrumbBack,
    context: BindingContext.IntelDetail,
    longLabel: "BACK", shortLabel: "Back", priority: 90))

  # =========================================================================
  # Messages Context (Unified Inbox)
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "Nav", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.listUp,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.listDown,
    context: BindingContext.Messages,
    longLabel: "NAV", shortLabel: "J", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusNext,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "Fcs", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyShiftTab, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusPrev,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "Fcs",
    priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusPrev,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "←",
    priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusPrev,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "H",
    priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusNext,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "→",
    priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.messageFocusNext,
    context: BindingContext.Messages,
    longLabel: "FOCUS", shortLabel: "L",
    priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyC, modifier: KeyModifier.None,
    actionKind: ActionKind.messageComposeToggle,
    context: BindingContext.Messages,
    longLabel: "COMPOSE", shortLabel: "New",
    priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.select,
    context: BindingContext.Messages,
    longLabel: "SELECT", shortLabel: "Sel",
    priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.deselect,
    context: BindingContext.Messages,
    longLabel: "BACK", shortLabel: "Back",
    priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyM, modifier: KeyModifier.None,
    actionKind: ActionKind.inboxJumpMessages,
    context: BindingContext.Messages,
    longLabel: "MESSAGES", shortLabel: "Msg",
    priority: 7))

  registerBinding(Binding(
    key: KeyCode.KeyR, modifier: KeyModifier.None,
    actionKind: ActionKind.inboxJumpReports,
    context: BindingContext.Messages,
    longLabel: "REPORTS", shortLabel: "Rpt",
    priority: 8))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.Ctrl,
    actionKind: ActionKind.messageScrollUp,
    context: BindingContext.Messages,
    longLabel: "SCROLL", shortLabel: "Up",
    priority: 9))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.Ctrl,
    actionKind: ActionKind.messageScrollDown,
    context: BindingContext.Messages,
    longLabel: "SCROLL", shortLabel: "Dn",
    priority: 9))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.messageScrollUp,
    context: BindingContext.Messages,
    longLabel: "SCROLL", shortLabel: "PgUp",
    priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.messageScrollDown,
    context: BindingContext.Messages,
    longLabel: "SCROLL", shortLabel: "PgDn",
    priority: 11))

  # =========================================================================
  # Build Modal Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategorySwitch,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY+", shortLabel: "Cat+", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListUp,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "Nav", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListUp,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "K", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListDown,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "Nav", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListDown,
    context: BindingContext.BuildModal,
    longLabel: "NAV", shortLabel: "J", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategoryPrev,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY-", shortLabel: "Cat-", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategoryPrev,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY-", shortLabel: "Cat-", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategorySwitch,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY+", shortLabel: "Cat+", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.buildCategorySwitch,
    context: BindingContext.BuildModal,
    longLabel: "CATEGORY+", shortLabel: "Cat+", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.buildQtyInc,
    context: BindingContext.BuildModal,
    longLabel: "QTY+", shortLabel: "+", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.None,
    actionKind: ActionKind.buildQtyInc,
    context: BindingContext.BuildModal,
    longLabel: "QTY+", shortLabel: "+", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.None,
    actionKind: ActionKind.buildQtyDec,
    context: BindingContext.BuildModal,
    longLabel: "QTY-", shortLabel: "-", priority: 12))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListPageUp,
    context: BindingContext.BuildModal,
    longLabel: "PGUP", shortLabel: "PgU", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.buildListPageDown,
    context: BindingContext.BuildModal,
    longLabel: "PGDN", shortLabel: "PgD", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closeBuildModal,
    context: BindingContext.BuildModal,
    longLabel: "CLOSE", shortLabel: "Esc", priority: 90))

  # =========================================================================
  # Queue Modal Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyUp, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListUp,
    context: BindingContext.QueueModal,
    longLabel: "NAV", shortLabel: "↑", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListUp,
    context: BindingContext.QueueModal,
    longLabel: "NAV", shortLabel: "K", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListDown,
    context: BindingContext.QueueModal,
    longLabel: "NAV", shortLabel: "↓", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListDown,
    context: BindingContext.QueueModal,
    longLabel: "NAV", shortLabel: "J", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyPageUp, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListPageUp,
    context: BindingContext.QueueModal,
    longLabel: "PGUP", shortLabel: "PgU", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyPageDown, modifier: KeyModifier.None,
    actionKind: ActionKind.queueListPageDown,
    context: BindingContext.QueueModal,
    longLabel: "PGDN", shortLabel: "PgD", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyD, modifier: KeyModifier.None,
    actionKind: ActionKind.queueDelete,
    context: BindingContext.QueueModal,
    longLabel: "DELETE", shortLabel: "Del", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closeQueueModal,
    context: BindingContext.QueueModal,
    longLabel: "CLOSE", shortLabel: "Esc", priority: 90))

  # =========================================================================
  # Population Transfer Modal Context
  # =========================================================================

  registerBinding(Binding(
    key: KeyCode.KeyTab, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferFocusNext,
    context: BindingContext.PopulationTransferModal,
    longLabel: "NEXT FIELD", shortLabel: "Tab", priority: 1))

  registerBinding(Binding(
    key: KeyCode.KeyShiftTab, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferFocusPrev,
    context: BindingContext.PopulationTransferModal,
    longLabel: "PREV FIELD", shortLabel: "S-Tab", priority: 2))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferDestPrev,
    context: BindingContext.PopulationTransferModal,
    longLabel: "DEST-", shortLabel: "←", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyH, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferDestPrev,
    context: BindingContext.PopulationTransferModal,
    longLabel: "DEST-", shortLabel: "H", priority: 3))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferDestNext,
    context: BindingContext.PopulationTransferModal,
    longLabel: "DEST+", shortLabel: "→", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyL, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferDestNext,
    context: BindingContext.PopulationTransferModal,
    longLabel: "DEST+", shortLabel: "L", priority: 4))

  registerBinding(Binding(
    key: KeyCode.KeyPlus, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferAmountInc,
    context: BindingContext.PopulationTransferModal,
    longLabel: "PTU+", shortLabel: "+", priority: 5))

  registerBinding(Binding(
    key: KeyCode.KeyMinus, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferAmountDec,
    context: BindingContext.PopulationTransferModal,
    longLabel: "PTU-", shortLabel: "-", priority: 6))

  registerBinding(Binding(
    key: KeyCode.KeyEnter, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferConfirm,
    context: BindingContext.PopulationTransferModal,
    longLabel: "STAGE", shortLabel: "OK", priority: 10))

  registerBinding(Binding(
    key: KeyCode.KeyD, modifier: KeyModifier.None,
    actionKind: ActionKind.populationTransferDeleteRoute,
    context: BindingContext.PopulationTransferModal,
    longLabel: "DELETE", shortLabel: "Del", priority: 11))

  registerBinding(Binding(
    key: KeyCode.KeyEscape, modifier: KeyModifier.None,
    actionKind: ActionKind.closePopulationTransferModal,
    context: BindingContext.PopulationTransferModal,
    longLabel: "CLOSE", shortLabel: "Esc", priority: 90))

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
    key: KeyCode.KeyK, modifier: KeyModifier.None,
    actionKind: ActionKind.expertHistoryPrev,
    context: BindingContext.ExpertMode,
    longLabel: "HISTORY", shortLabel: "K", priority: 20))

  registerBinding(Binding(
    key: KeyCode.KeyDown, modifier: KeyModifier.None,
    actionKind: ActionKind.expertHistoryNext,
    context: BindingContext.ExpertMode,
    longLabel: "HISTORY", shortLabel: "Hist", priority: 21))

  registerBinding(Binding(
    key: KeyCode.KeyJ, modifier: KeyModifier.None,
    actionKind: ActionKind.expertHistoryNext,
    context: BindingContext.ExpertMode,
    longLabel: "HISTORY", shortLabel: "J", priority: 21))
  registerBinding(Binding(
    key: KeyCode.KeyBackspace, modifier: KeyModifier.None,
    actionKind: ActionKind.expertInputBackspace,
    context: BindingContext.ExpertMode,
    longLabel: "DELETE", shortLabel: "Del", priority: 30))

  registerBinding(Binding(
    key: KeyCode.KeyLeft, modifier: KeyModifier.None,
    actionKind: ActionKind.expertCursorLeft,
    context: BindingContext.ExpertMode,
    longLabel: "CURSOR", shortLabel: "Cur", priority: 31))

  registerBinding(Binding(
    key: KeyCode.KeyRight, modifier: KeyModifier.None,
    actionKind: ActionKind.expertCursorRight,
    context: BindingContext.ExpertMode,
    longLabel: "CURSOR", shortLabel: "Cur", priority: 32))

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
      of KeyCode.KeyO: 1   # Overview
      of KeyCode.KeyY: 2   # Colony (Planets)
      of KeyCode.KeyF: 3   # Fleet
      of KeyCode.KeyT: 4   # Tech (Research)
      of KeyCode.KeyE: 5   # Espionage
      of KeyCode.KeyG: 6   # General (Economy)
      of KeyCode.KeyI: 8   # Intel db
      of KeyCode.KeyN: 10  # Messages
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
      of KeyCode.KeyK: HexDirection.NorthWest
      of KeyCode.KeyJ: HexDirection.SouthEast
      of KeyCode.KeyH: HexDirection.West
      of KeyCode.KeyL: HexDirection.East
      else: HexDirection.East
    return some(actionMoveCursor(dir))

  # Selection
  of ActionKind.select:
    return some(actionSelect())
  of ActionKind.deselect:
    return some(actionDeselect())
  of ActionKind.toggleFleetSelect:
    return some(actionToggleFleetSelect(model.ui.selectedIdx))
  of ActionKind.fleetSortToggle:
    return some(actionFleetSortToggle())
  of ActionKind.fleetBatchCommand:
    return some(actionFleetBatchCommand())
  of ActionKind.fleetBatchROE:
    return some(actionFleetBatchROE())
  of ActionKind.fleetBatchZeroTurn:
    return some(actionFleetBatchZeroTurn())

  # Expert mode
  of ActionKind.enterExpertMode:
    return some(actionEnterExpertMode())
  of ActionKind.exitExpertMode:
    return some(actionExitExpertMode())
  of ActionKind.expertSubmit:
    return some(actionExpertSubmit())
  of ActionKind.expertInputBackspace:
    return some(actionExpertInputBackspace())
  of ActionKind.expertCursorLeft:
    return some(actionExpertCursorLeft())
  of ActionKind.expertCursorRight:
    return some(actionExpertCursorRight())
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

  of ActionKind.toggleHelpOverlay:
    return some(actionToggleHelpOverlay())

  of ActionKind.switchFleetView:
    return some(actionSwitchFleetView())
  of ActionKind.cycleColony:
    let reverse = key in {KeyCode.KeyLeft, KeyCode.KeyH}
    return some(actionCycleColony(reverse))
  of ActionKind.intelEditNote:
    return some(actionIntelEditNote())
  of ActionKind.intelDetailNext:
    return some(actionIntelDetailNext())
  of ActionKind.intelDetailPrev:
    return some(actionIntelDetailPrev())
  of ActionKind.intelNoteAppend:
    return some(actionIntelNoteAppend(""))
  of ActionKind.intelNoteBackspace:
    return some(actionIntelNoteBackspace())
  of ActionKind.intelNoteCursorLeft:
    return some(actionIntelNoteCursorLeft())
  of ActionKind.intelNoteCursorRight:
    return some(actionIntelNoteCursorRight())
  of ActionKind.intelNoteCursorUp:
    return some(actionIntelNoteCursorUp())
  of ActionKind.intelNoteCursorDown:
    return some(actionIntelNoteCursorDown())
  of ActionKind.intelNoteInsertNewline:
    return some(actionIntelNoteInsertNewline())
  of ActionKind.intelNoteDelete:
    return some(actionIntelNoteDelete())
  of ActionKind.intelNoteSave:
    return some(actionIntelNoteSave())
  of ActionKind.intelNoteCancel:
    return some(actionIntelNoteCancel())
  of ActionKind.intelFleetPopupClose:
    return some(actionIntelFleetPopupClose())
  of ActionKind.entryCursorLeft:
    return some(actionEntryCursorLeft())
  of ActionKind.entryCursorRight:
    return some(actionEntryCursorRight())
  of ActionKind.entryDelete:
    return some(actionEntryDelete())
  of ActionKind.lobbyCursorLeft:
    return some(actionLobbyCursorLeft())
  of ActionKind.lobbyCursorRight:
    return some(actionLobbyCursorRight())
  of ActionKind.lobbyDelete:
    return some(actionLobbyDelete())

  # Lobby actions (handled separately in mapKeyToAction)
  of ActionKind.lobbyReturn:
    return some(actionLobbyReturn())

  # Build modal actions
  of ActionKind.openBuildModal:
    # Will be handled in acceptor to get colony ID
    return some(actionOpenBuildModal(0))
  of ActionKind.toggleAutoRepair:
    return some(actionToggleAutoRepair())
  of ActionKind.toggleAutoLoadMarines:
    return some(actionToggleAutoLoadMarines())
  of ActionKind.toggleAutoLoadFighters:
    return some(actionToggleAutoLoadFighters())
  of ActionKind.closeBuildModal:
    return some(actionCloseBuildModal())
  of ActionKind.buildCategorySwitch:
    return some(actionBuildCategorySwitch())
  of ActionKind.buildCategoryPrev:
    return some(actionBuildCategoryPrev())
  of ActionKind.buildListUp:
    return some(actionBuildListUp())
  of ActionKind.buildListDown:
    return some(actionBuildListDown())
  of ActionKind.buildListPageUp:
    return some(actionBuildListPageUp())
  of ActionKind.buildListPageDown:
    return some(actionBuildListPageDown())
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
  of ActionKind.buildQtyInc:
    return some(actionBuildQtyInc())
  of ActionKind.buildQtyDec:
    return some(actionBuildQtyDec())
  of ActionKind.openQueueModal:
    return some(actionOpenQueueModal())
  of ActionKind.closeQueueModal:
    return some(actionCloseQueueModal())
  of ActionKind.queueListUp:
    return some(actionQueueListUp())
  of ActionKind.queueListDown:
    return some(actionQueueListDown())
  of ActionKind.queueListPageUp:
    return some(actionQueueListPageUp())
  of ActionKind.queueListPageDown:
    return some(actionQueueListPageDown())
  of ActionKind.queueDelete:
    return some(actionQueueDelete())
  of ActionKind.openPopulationTransferModal:
    return some(actionOpenPopulationTransferModal())
  of ActionKind.closePopulationTransferModal:
    return some(actionClosePopulationTransferModal())
  of ActionKind.populationTransferFocusNext:
    return some(actionPopulationTransferFocusNext())
  of ActionKind.populationTransferFocusPrev:
    return some(actionPopulationTransferFocusPrev())
  of ActionKind.populationTransferDestPrev:
    return some(actionPopulationTransferDestPrev())
  of ActionKind.populationTransferDestNext:
    return some(actionPopulationTransferDestNext())
  of ActionKind.populationTransferAmountInc:
    return some(actionPopulationTransferAmountInc())
  of ActionKind.populationTransferAmountDec:
    return some(actionPopulationTransferAmountDec())
  of ActionKind.populationTransferConfirm:
    return some(actionPopulationTransferConfirm())
  of ActionKind.populationTransferDeleteRoute:
    return some(actionPopulationTransferDeleteRoute())
  of ActionKind.stageTerraformCommand:
    return some(actionStageTerraformCommand())
  
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
  of ActionKind.fleetDetailPageUp:
    return some(actionFleetDetailPageUp())
  of ActionKind.fleetDetailPageDown:
    return some(actionFleetDetailPageDown())
  of ActionKind.fleetDetailDigitInput:
    # This is handled specially - digit passed via gameActionData
    return none(Proposal)
  of ActionKind.fleetDetailOpenZTC:
    return some(actionFleetDetailOpenZTC())
  of ActionKind.fleetDetailSelectZTC:
    return some(actionFleetDetailSelectZTC())

  # Inbox / Messages actions
  of ActionKind.messageFocusNext:
    return some(actionMessageFocusNext())
  of ActionKind.messageFocusPrev:
    return some(actionMessageFocusPrev())
  of ActionKind.messageComposeToggle:
    return some(actionMessageComposeToggle())
  of ActionKind.messageComposeStartWithChar:
    # Handled specially with gameActionData payload.
    return none(Proposal)
  of ActionKind.messageComposeDelete:
    return some(actionMessageComposeDelete())
  of ActionKind.messageScrollUp:
    return some(actionMessageScrollUp())
  of ActionKind.messageScrollDown:
    return some(actionMessageScrollDown())
  of ActionKind.inboxJumpMessages:
    return some(actionInboxJumpMessages())
  of ActionKind.inboxJumpReports:
    return some(actionInboxJumpReports())
  of ActionKind.inboxExpandTurn:
    return some(actionInboxExpandTurn())
  of ActionKind.inboxCollapseTurn:
    return some(actionInboxCollapseTurn())
  of ActionKind.inboxReportUp:
    return some(actionInboxReportUp())
  of ActionKind.inboxReportDown:
    return some(actionInboxReportDown())

  # Research actions
  of ActionKind.researchAdjustInc:
    return some(actionResearchAdjustInc())
  of ActionKind.researchAdjustDec:
    return some(actionResearchAdjustDec())
  of ActionKind.researchAdjustFineInc:
    return some(actionResearchAdjustFineInc())
  of ActionKind.researchAdjustFineDec:
    return some(actionResearchAdjustFineDec())
  of ActionKind.researchClearAllocation:
    return some(actionResearchClearAllocation())
  of ActionKind.researchDigitInput:
    # This is handled specially - digit passed via gameActionData
    return none(Proposal)

  # Espionage actions
  of ActionKind.espionageFocusNext:
    return some(actionEspionageFocusNext())
  of ActionKind.espionageFocusPrev:
    return some(actionEspionageFocusPrev())
  of ActionKind.espionageSelectEbp:
    return some(actionEspionageSelectEbp())
  of ActionKind.espionageSelectCip:
    return some(actionEspionageSelectCip())
  of ActionKind.espionageBudgetAdjustInc:
    return some(actionEspionageBudgetAdjustInc())
  of ActionKind.espionageBudgetAdjustDec:
    return some(actionEspionageBudgetAdjustDec())
  of ActionKind.espionageQueueAdd:
    return some(actionEspionageQueueAdd())
  of ActionKind.espionageQueueDelete:
    return some(actionEspionageQueueDelete())
  of ActionKind.espionageClearBudget:
    return some(actionEspionageClearBudget())

  # Economy actions
  of ActionKind.economyFocusNext:
    return some(actionEconomyFocusNext())
  of ActionKind.economyFocusPrev:
    return some(actionEconomyFocusPrev())
  of ActionKind.economyTaxInc:
    return some(actionEconomyTaxInc())
  of ActionKind.economyTaxDec:
    return some(actionEconomyTaxDec())
  of ActionKind.economyTaxFineInc:
    return some(actionEconomyTaxFineInc())
  of ActionKind.economyTaxFineDec:
    return some(actionEconomyTaxFineDec())
  of ActionKind.economyDiplomacyAction:
    return some(actionEconomyDiplomacyAction())
  of ActionKind.exportMap:
    return some(actionExportMap())
  of ActionKind.economyDiplomacyPropose:
    return some(actionEconomyDiplomacyPropose())
  of ActionKind.economyDiplomacyAccept:
    return some(actionEconomyDiplomacyAccept())
  of ActionKind.economyDiplomacyReject:
    return some(actionEconomyDiplomacyReject())

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

proc backActionForState(model: TuiModel): Option[Proposal] =
  ## Return the layered back action for current state
  if model.ui.submitConfirmActive:
    return some(actionSubmitCancel())
  if model.ui.quitConfirmationActive:
    return some(actionQuitCancel())
  if model.ui.intelNoteEditActive:
    return some(actionIntelNoteCancel())
  if model.ui.mode == ViewMode.IntelDetail and
      model.ui.intelDetailFleetPopupActive:
    return some(actionIntelFleetPopupClose())
  if model.ui.queueModal.active:
    return some(actionCloseQueueModal())
  if model.ui.populationTransferModal.active:
    return some(actionClosePopulationTransferModal())
  if model.ui.buildModal.active:
    return some(actionCloseBuildModal())
  if model.ui.mode == ViewMode.FleetDetail:
    if model.ui.fleetDetailModal.subModal != FleetSubModal.None:
      return some(actionFleetDetailCancel())
    return some(actionCloseFleetDetailModal())
  if model.ui.expertModeActive:
    return some(actionExitExpertMode())
  if model.ui.appPhase == AppPhase.Lobby:
    if model.ui.entryModal.mode == EntryModalMode.ImportNsec:
      return some(actionEntryImportCancel())
    if model.ui.entryModal.editingRelay:
      return some(actionEntryRelayConfirm())
    if model.ui.entryModal.mode == EntryModalMode.CreateGame:
      return some(actionCreateGameCancel())
    if model.ui.entryModal.mode == EntryModalMode.ManageGames:
      return some(actionManageGamesCancel())
    if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
      return some(actionEntryIdentityMenu())
  if model.ui.mode in {
      ViewMode.PlanetDetail,
      ViewMode.IntelDetail}:
    return some(actionBreadcrumbBack())
  none(Proposal)

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

  if key == KeyCode.KeyEscape and modifier == KeyModifier.None:
    if model.ui.identityDeleteConfirmActive:
      return none(Proposal)
    let backAction = backActionForState(model)
    if backAction.isSome:
      return backAction
  if model.ui.mode == ViewMode.IntelDetail and
      model.ui.intelDetailFleetPopupActive:
    return none(Proposal)

  # Ctrl+X always quits (global)
  if key == KeyCode.KeyX and modifier == KeyModifier.Ctrl:
    return some(actionQuit())

  # Quit confirmation modal - takes precedence over everything
  if model.ui.quitConfirmationActive:
    case key
    of KeyCode.KeyY:
      return some(actionQuitConfirm())
    of KeyCode.KeyN:
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

  # Submit confirmation modal - takes precedence over most bindings
  if model.ui.submitConfirmActive:
    case key
    of KeyCode.KeyEnter:
      return some(actionSubmitConfirm())
    else:
      return none(Proposal)  # Swallow all other input

  # Export confirmation popup - any key dismisses it
  if model.ui.exportConfirmActive:
    return some(actionDismissExportConfirm())

  if model.ui.queueModal.active and modifier == KeyModifier.None:
    if key != KeyCode.KeyEscape:
      let queueResult = lookupAndDispatch(
        key, KeyModifier.None, BindingContext.QueueModal, model
      )
      if queueResult.isSome:
        return queueResult
      return none(Proposal)

  if model.ui.populationTransferModal.active:
    if key != KeyCode.KeyEscape:
      let transferResult = lookupAndDispatch(
        key, modifier,
        BindingContext.PopulationTransferModal,
        model
      )
      if transferResult.isSome:
        return transferResult
      if modifier == KeyModifier.Shift and key == KeyCode.KeyPlus:
        let plusResult = lookupAndDispatch(
          key,
          KeyModifier.None,
          BindingContext.PopulationTransferModal,
          model
        )
        if plusResult.isSome:
          return plusResult
      return none(Proposal)

  # Build modal mode: use registry
  if model.ui.buildModal.active:
    if key != KeyCode.KeyEscape:
      let buildResult = lookupAndDispatch(
        key,
        modifier,
        BindingContext.BuildModal,
        model
      )
      if buildResult.isSome:
        return buildResult
      if modifier == KeyModifier.Shift and key == KeyCode.KeyPlus:
        let fallback = lookupAndDispatch(
          key,
          KeyModifier.None,
          BindingContext.BuildModal,
          model
        )
        if fallback.isSome:
          return fallback
      return none(Proposal)

  # Fleet detail view mode: use registry
  if model.ui.mode == ViewMode.FleetDetail:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector and
        modifier == KeyModifier.None and key == KeyCode.KeyX:
      return some(actionFleetDetailDigitInput('X'))

    # Handle digit keys for quick entry in sub-modals
    if model.ui.fleetDetailModal.subModal in {
        FleetSubModal.CommandPicker,
        FleetSubModal.ROEPicker,
        FleetSubModal.ZTCPicker,
        FleetSubModal.SystemPicker,
        FleetSubModal.ShipSelector,
        FleetSubModal.CargoParams,
        FleetSubModal.FighterParams}:
      if modifier == KeyModifier.None:
        let digitChar = case key
          of KeyCode.Key0: '0'
          of KeyCode.Key1: '1'
          of KeyCode.Key2: '2'
          of KeyCode.Key3: '3'
          of KeyCode.Key4: '4'
          of KeyCode.Key5: '5'
          of KeyCode.Key6: '6'
          of KeyCode.Key7: '7'
          of KeyCode.Key8: '8'
          of KeyCode.Key9: '9'
          else: '\0'
        if digitChar != '\0':
          return some(actionFleetDetailDigitInput(
            digitChar))
    # Handle letter keys for SystemPicker filter
    if model.ui.fleetDetailModal.subModal ==
        FleetSubModal.SystemPicker:
      if modifier == KeyModifier.None:
        let letterChar = case key
          of KeyCode.KeyA: 'A'
          of KeyCode.KeyB: 'B'
          of KeyCode.KeyC: 'C'
          of KeyCode.KeyD: 'D'
          of KeyCode.KeyE: 'E'
          of KeyCode.KeyF: 'F'
          of KeyCode.KeyG: 'G'
          of KeyCode.KeyH: 'H'
          of KeyCode.KeyI: 'I'
          of KeyCode.KeyJ: 'J'
          of KeyCode.KeyK: 'K'
          of KeyCode.KeyL: 'L'
          of KeyCode.KeyM: 'M'
          of KeyCode.KeyN: 'N'
          of KeyCode.KeyO: 'O'
          of KeyCode.KeyP: 'P'
          of KeyCode.KeyQ: 'Q'
          of KeyCode.KeyR: 'R'
          of KeyCode.KeyS: 'S'
          of KeyCode.KeyT: 'T'
          of KeyCode.KeyU: 'U'
          of KeyCode.KeyV: 'V'
          of KeyCode.KeyW: 'W'
          of KeyCode.KeyX: 'X'
          of KeyCode.KeyY: 'Y'
          of KeyCode.KeyZ: 'Z'
          else: '\0'
        if letterChar != '\0':
          return some(actionFleetDetailDigitInput(
            letterChar))
    
    if key != KeyCode.KeyEscape:
      let fleetDetailResult = lookupAndDispatch(key, modifier,
          BindingContext.FleetDetail, model)
      if fleetDetailResult.isSome:
        return fleetDetailResult
      # Allow global bindings to pass through, block other keys
      if modifier != ViewModifier:
        return none(Proposal)

  # Research view digit input
  if model.ui.mode == ViewMode.Research and
      not model.ui.expertModeActive and
      modifier == KeyModifier.None:
    let digitChar = case key
      of KeyCode.Key0: '0'
      of KeyCode.Key1: '1'
      of KeyCode.Key2: '2'
      of KeyCode.Key3: '3'
      of KeyCode.Key4: '4'
      of KeyCode.Key5: '5'
      of KeyCode.Key6: '6'
      of KeyCode.Key7: '7'
      of KeyCode.Key8: '8'
      of KeyCode.Key9: '9'
      else: '\0'
    if digitChar != '\0':
      return some(actionResearchDigitInput(digitChar))

  if model.ui.mode == ViewMode.Fleets and
      model.ui.fleetViewMode == FleetViewMode.ListView and
      not model.ui.expertModeActive and
      modifier == KeyModifier.None:
    # Fleet label jump: type 2-char label (e.g. A1, B3) to jump to fleet
    # Excludes letters bound in Fleets context: H/J/K(nav), S(sort), V(view),
    # X(select), C(batch cmd), R(batch ROE), Z(batch ZTC)
    let jumpChar = case key
      of KeyCode.Key0: '0'
      of KeyCode.Key1: '1'
      of KeyCode.Key2: '2'
      of KeyCode.Key3: '3'
      of KeyCode.Key4: '4'
      of KeyCode.Key5: '5'
      of KeyCode.Key6: '6'
      of KeyCode.Key7: '7'
      of KeyCode.Key8: '8'
      of KeyCode.Key9: '9'
      of KeyCode.KeyA: 'A'
      of KeyCode.KeyB: 'B'
      of KeyCode.KeyD: 'D'
      of KeyCode.KeyE: 'E'
      of KeyCode.KeyF: 'F'
      of KeyCode.KeyG: 'G'
      of KeyCode.KeyI: 'I'
      of KeyCode.KeyM: 'M'
      of KeyCode.KeyN: 'N'
      of KeyCode.KeyO: 'O'
      of KeyCode.KeyP: 'P'
      of KeyCode.KeyQ: 'Q'
      of KeyCode.KeyT: 'T'
      of KeyCode.KeyU: 'U'
      of KeyCode.KeyW: 'W'
      of KeyCode.KeyY: 'Y'
      else: '\0'
    if jumpChar != '\0':
      return some(actionFleetDigitJump(jumpChar))

  # Fleet console SystemView jump: type 2-char label to jump to
  # system (Systems pane) or fleet (Fleets pane).
  # Reserved in Fleets context: J/K (up/down), H/L (pane nav),
  # S (sort), V (view), X (select), C (cmd), R (ROE), Z (ZTC)
  if model.ui.mode == ViewMode.Fleets and
      model.ui.fleetViewMode == FleetViewMode.SystemView and
      not model.ui.expertModeActive and
      modifier == KeyModifier.None:
    let jumpChar = case key
      of KeyCode.Key0: '0'
      of KeyCode.Key1: '1'
      of KeyCode.Key2: '2'
      of KeyCode.Key3: '3'
      of KeyCode.Key4: '4'
      of KeyCode.Key5: '5'
      of KeyCode.Key6: '6'
      of KeyCode.Key7: '7'
      of KeyCode.Key8: '8'
      of KeyCode.Key9: '9'
      of KeyCode.KeyA: 'A'
      of KeyCode.KeyB: 'B'
      of KeyCode.KeyD: 'D'
      of KeyCode.KeyE: 'E'
      of KeyCode.KeyF: 'F'
      of KeyCode.KeyG: 'G'
      of KeyCode.KeyI: 'I'
      of KeyCode.KeyM: 'M'
      of KeyCode.KeyN: 'N'
      of KeyCode.KeyO: 'O'
      of KeyCode.KeyP: 'P'
      of KeyCode.KeyQ: 'Q'
      of KeyCode.KeyT: 'T'
      of KeyCode.KeyU: 'U'
      of KeyCode.KeyW: 'W'
      of KeyCode.KeyY: 'Y'
      else: '\0'
    if jumpChar != '\0':
      if model.ui.fleetConsoleFocus == FleetConsoleFocus.SystemsPane:
        return some(actionFleetConsoleSystemJump(jumpChar))
      elif model.ui.fleetConsoleFocus == FleetConsoleFocus.FleetsPane:
        return some(actionFleetConsoleFleetJump(jumpChar))
  # Excludes N (note editing)
  if model.ui.mode == ViewMode.IntelDb and
      not model.ui.expertModeActive and
      modifier == KeyModifier.None:
    let jumpChar = case key
      of KeyCode.Key0: '0'
      of KeyCode.Key1: '1'
      of KeyCode.Key2: '2'
      of KeyCode.Key3: '3'
      of KeyCode.Key4: '4'
      of KeyCode.Key5: '5'
      of KeyCode.Key6: '6'
      of KeyCode.Key7: '7'
      of KeyCode.Key8: '8'
      of KeyCode.Key9: '9'
      of KeyCode.KeyA: 'A'
      of KeyCode.KeyB: 'B'
      of KeyCode.KeyC: 'C'
      of KeyCode.KeyD: 'D'
      of KeyCode.KeyE: 'E'
      of KeyCode.KeyF: 'F'
      of KeyCode.KeyG: 'G'
      of KeyCode.KeyH: 'H'
      of KeyCode.KeyI: 'I'
      of KeyCode.KeyL: 'L'
      of KeyCode.KeyM: 'M'
      of KeyCode.KeyO: 'O'
      of KeyCode.KeyP: 'P'
      of KeyCode.KeyQ: 'Q'
      of KeyCode.KeyR: 'R'
      of KeyCode.KeyS: 'S'
      of KeyCode.KeyT: 'T'
      of KeyCode.KeyU: 'U'
      of KeyCode.KeyV: 'V'
      of KeyCode.KeyW: 'W'
      of KeyCode.KeyX: 'X'
      of KeyCode.KeyY: 'Y'
      of KeyCode.KeyZ: 'Z'
      else: '\0'
    if jumpChar != '\0':
      return some(actionIntelDigitJump(jumpChar))

  # Planets jump: type 2-char sector label (e.g. A01, B03) to jump
  # Excludes B (build), Q (queue)
  if model.ui.mode == ViewMode.Planets and
      not model.ui.expertModeActive and
      modifier == KeyModifier.None:
    let jumpChar = case key
      of KeyCode.Key0: '0'
      of KeyCode.Key1: '1'
      of KeyCode.Key2: '2'
      of KeyCode.Key3: '3'
      of KeyCode.Key4: '4'
      of KeyCode.Key5: '5'
      of KeyCode.Key6: '6'
      of KeyCode.Key7: '7'
      of KeyCode.Key8: '8'
      of KeyCode.Key9: '9'
      of KeyCode.KeyA: 'A'
      of KeyCode.KeyC: 'C'
      of KeyCode.KeyD: 'D'
      of KeyCode.KeyE: 'E'
      of KeyCode.KeyF: 'F'
      of KeyCode.KeyG: 'G'
      of KeyCode.KeyH: 'H'
      of KeyCode.KeyI: 'I'
      of KeyCode.KeyL: 'L'
      of KeyCode.KeyM: 'M'
      of KeyCode.KeyN: 'N'
      of KeyCode.KeyO: 'O'
      of KeyCode.KeyP: 'P'
      of KeyCode.KeyR: 'R'
      of KeyCode.KeyS: 'S'
      of KeyCode.KeyT: 'T'
      of KeyCode.KeyU: 'U'
      of KeyCode.KeyV: 'V'
      of KeyCode.KeyW: 'W'
      of KeyCode.KeyX: 'X'
      of KeyCode.KeyY: 'Y'
      of KeyCode.KeyZ: 'Z'
      else: '\0'
    if jumpChar != '\0':
      return some(actionColonyDigitJump(jumpChar))

  # Expert mode: use registry
  if model.ui.expertModeActive and modifier == KeyModifier.None:
    if key != KeyCode.KeyEscape:
      let expertResult = lookupAndDispatch(key, KeyModifier.None,
          BindingContext.ExpertMode, model)
      if expertResult.isSome:
        return expertResult
      # Other keys add to input buffer - handled by acceptor
      return none(Proposal)

  # Lobby phase: special handling for text input modes
  if model.ui.appPhase == AppPhase.Lobby:
    # Identity delete confirmation popup takes priority
    if model.ui.identityDeleteConfirmActive:
      case key
      of KeyCode.KeyY:
        return some(actionEntryIdentityDeleteConfirm())
      of KeyCode.KeyN:
        return some(actionEntryIdentityDeleteCancel())
      else:
        return none(Proposal)

    if model.ui.lobbyInputMode != LobbyInputMode.None:
      case key
      of KeyCode.KeyEnter:
        return some(actionLobbyJoinSubmit())
      of KeyCode.KeyBackspace:
        return some(actionLobbyBackspace())
      of KeyCode.KeyDelete:
        return some(actionLobbyDelete())
      of KeyCode.KeyLeft:
        return some(actionLobbyCursorLeft())
      of KeyCode.KeyRight:
        return some(actionLobbyCursorRight())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    if model.ui.entryModal.mode == EntryModalMode.PasswordPrompt:
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryPasswordConfirm())
      of KeyCode.KeyEscape:
        return some(actionQuit())
      of KeyCode.KeyBackspace:
        return some(actionEntryPasswordBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      of KeyCode.KeyLeft:
        return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        return some(actionEntryCursorRight())
      of KeyCode.KeyH:
        return some(actionEntryToggleMask())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    if model.ui.entryModal.mode == EntryModalMode.ImportNsec:
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryImportConfirm())
      of KeyCode.KeyEscape:
        return some(actionEntryImportCancel())
      of KeyCode.KeyBackspace:
        return some(actionEntryImportBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      of KeyCode.KeyLeft:
        return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        return some(actionEntryCursorRight())
      of KeyCode.KeyH:
        return some(actionEntryToggleMask())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.editingRelay:
      case key
      of KeyCode.KeyEnter, KeyCode.KeyEscape:
        return some(actionEntryRelayConfirm())
      of KeyCode.KeyBackspace:
        return some(actionEntryRelayBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      of KeyCode.KeyLeft:
        return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        return some(actionEntryCursorRight())
      else:
        if modifier != ViewModifier:
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
        if model.ui.entryModal.createField == CreateGameField.GameName:
          return some(actionEntryCursorLeft())
        return some(actionCreateGameLeft())
      of KeyCode.KeyRight:
        if model.ui.entryModal.createField == CreateGameField.GameName:
          return some(actionEntryCursorRight())
        return some(actionCreateGameRight())
      of KeyCode.KeyEnter:
        return some(actionCreateGameConfirm())
      of KeyCode.KeyBackspace:
        return some(actionCreateGameBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.ManageGames:
      case key
      of KeyCode.KeyEscape:
        return some(actionManageGamesCancel())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
      case key
      of KeyCode.KeyEscape:
        return some(actionEntryIdentityMenu())
      of KeyCode.KeyUp:
        return some(actionEntryUp())
      of KeyCode.KeyDown:
        return some(actionEntryDown())
      of KeyCode.KeyEnter:
        return some(actionEntryIdentityActivate())
      of KeyCode.KeyI:
        return some(actionEntryImport())
      of KeyCode.KeyN:
        return some(actionEntryIdentityCreate())
      of KeyCode.KeyD:
        return some(actionEntryIdentityDelete())
      of KeyCode.KeyP:
        return some(actionEntryChangePassword())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
      case key
      of KeyCode.KeyEscape:
        return some(actionEntryPlayerGamesMenu())
      of KeyCode.KeyUp, KeyCode.KeyK:
        return some(actionEntryUp())
      of KeyCode.KeyDown, KeyCode.KeyJ:
        return some(actionEntryDown())
      of KeyCode.KeyPageUp:
        return some(actionEntryPageUp())
      of KeyCode.KeyPageDown:
        return some(actionEntryPageDown())
      of KeyCode.KeyEnter:
        return some(actionEntryPlayerGamesSelect())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.CreatePasswordPrompt:
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryCreatePasswordConfirm())
      of KeyCode.KeyEscape:
        return some(actionQuit())
      of KeyCode.KeyBackspace:
        return some(actionEntryCreatePasswordBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      of KeyCode.KeyLeft:
        return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        return some(actionEntryCursorRight())
      of KeyCode.KeyH:
        return some(actionEntryToggleMask())
      else:
        if modifier != ViewModifier:
          return none(Proposal)

    elif model.ui.entryModal.mode == EntryModalMode.ChangePasswordPrompt:
      case key
      of KeyCode.KeyEnter:
        return some(actionEntryChangePasswordConfirm())
      of KeyCode.KeyEscape:
        return some(actionEntryIdentityMenu())
      of KeyCode.KeyBackspace:
        return some(actionEntryChangePasswordBackspace())
      of KeyCode.KeyDelete:
        return some(actionEntryDelete())
      of KeyCode.KeyLeft:
        return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        return some(actionEntryCursorRight())
      of KeyCode.KeyH:
        return some(actionEntryToggleMask())
      else:
        if modifier != ViewModifier:
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
      of KeyCode.KeyDelete:
        if model.ui.entryModal.focus in {
            EntryModalFocus.InviteCode,
            EntryModalFocus.RelayUrl}:
          return some(actionEntryDelete())
        else:
          return none(Proposal)
      of KeyCode.KeyLeft:
        if model.ui.entryModal.focus in {
            EntryModalFocus.InviteCode,
            EntryModalFocus.RelayUrl}:
          return some(actionEntryCursorLeft())
      of KeyCode.KeyRight:
        if model.ui.entryModal.focus in {
            EntryModalFocus.InviteCode,
            EntryModalFocus.RelayUrl}:
          return some(actionEntryCursorRight())
      of KeyCode.KeyW:
        if modifier == KeyModifier.Ctrl:
          return some(actionEntryIdentityMenu())
      of KeyCode.KeyG:
        if modifier == KeyModifier.Ctrl:
          return some(actionEntryPlayerGamesMenu())
      else:
        if modifier != ViewModifier:
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
  let ctx = viewModeToContext(model.ui.mode)
  let ctxResult = lookupAndDispatch(key, modifier, ctx, model)
  if ctxResult.isSome:
    return ctxResult

  none(Proposal)

# =============================================================================
# Bar Item Building
# =============================================================================

proc buildBarItems*(model: TuiModel, useShortLabels: bool): seq[BarItem] =
  ## Build bar items based on current model state
  ## Always show global view tabs (except in expert mode)
  ## Modals and views have their own footers for context-specific actions

  result = @[]

  # Determine which bindings to show
  # Always show view tabs in all views for consistent navigation
  let showGlobalTabs = model.ui.appPhase == AppPhase.InGame and
      not model.ui.expertModeActive

  if showGlobalTabs:
  # Show view tabs (Ctrl+Letter) + quit + expert mode hint
    let globalBindings = getGlobalBindings()
    var idx = 0
    for b in globalBindings:
      if b.hidden:
        continue
      let labelRaw = if useShortLabels: b.shortLabel else: b.longLabel
      let labelParts = labelRaw.split("|", maxsplit = 1)
      let hasPipe = labelParts.len > 1
      let labelBefore = if hasPipe: labelParts[0] else: ""
      let labelAfter = if hasPipe: labelParts[1] else: labelRaw
      let label = if hasPipe: labelBefore & labelAfter else: labelRaw
      let isSelected = case b.key
        of KeyCode.KeyO: model.ui.mode == ViewMode.Overview
        of KeyCode.KeyY: model.ui.mode == ViewMode.Planets
        of KeyCode.KeyF: model.ui.mode == ViewMode.Fleets
        of KeyCode.KeyT: model.ui.mode == ViewMode.Research
        of KeyCode.KeyE: model.ui.mode == ViewMode.Espionage
        of KeyCode.KeyG: model.ui.mode == ViewMode.Economy
        of KeyCode.KeyI:
          model.ui.mode in {ViewMode.IntelDb, ViewMode.IntelDetail}
        of KeyCode.KeyN: model.ui.mode == ViewMode.Messages
        else: false

      let mode = if isSelected: BarItemMode.Selected
                 elif idx mod 2 == 1: BarItemMode.UnselectedAlt
                 else: BarItemMode.Unselected

      # Show just the uppercase letter for view tabs (modifier shown as prefix)
      let keyDisp = formatKeyCode(b.key).toUpperAscii()

      result.add(BarItem(
        keyDisplay: keyDisp,
        label: label,
        longLabel: b.longLabel,
        shortLabel: b.shortLabel,
        labelBefore: labelBefore,
        labelAfter: labelAfter,
        labelHasPipe: hasPipe,
        mode: mode,
        binding: b
      ))
      idx.inc
  else:
    # Expert mode - show their specific actions
    let ctx = BindingContext.ExpertMode

    let bindings = getBindingsForContext(ctx)

    # Group arrow keys together as ↑↓ or ←→
    var seenNavUp = false
    var seenNavLeft = false

    var idx = 0
    for b in bindings:
      if b.hidden:
        continue
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
      let labelRaw = if useShortLabels: b.shortLabel else: b.longLabel
      let labelParts = labelRaw.split("|", maxsplit = 1)
      let hasPipe = labelParts.len > 1
      let labelBefore = if hasPipe: labelParts[0] else: ""
      let labelAfter = if hasPipe: labelParts[1] else: labelRaw
      let label = if hasPipe: labelBefore & labelAfter else: labelRaw

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
        labelBefore: labelBefore,
        labelAfter: labelAfter,
        labelHasPipe: hasPipe,
        mode: mode,
        binding: b
      ))
      idx.inc
