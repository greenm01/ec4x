## Client-side turn report generator
##
## The engine does not generate narrative reports (per intel.md
## architecture decision: engine = data, client = presentation).
## This module interprets PlayerState and GameEvents to produce
## human-readable ReportEntry items for the inbox/reports view.
##
## Currently generates:
##   - Turn 1 welcome/intro report with House lore, Prestige
##     objectives, and ETAC/Scout early-game hints.

import std/tables
import ../../engine/types/player_state as ps_types
import ../sam/tui_model

# =============================================================================
# House Lore Table
# =============================================================================

type HouseLore = tuple[tag: string, blurb: string]

const HouseLoreTable: array[12, HouseLore] = [
  (
    tag: "valerian",
    blurb: "The oldest of the dynatoi, claiming unbroken lineage " &
      "from the First Expansion. Your ancestral palace orbits a " &
      "dying red giant. Family tradition demands every heir make " &
      "a pilgrimage there before assuming the mantle of leadership."
  ),
  (
    tag: "thelon",
    blurb: "You rose to power during the Collapse Wars by playing " &
      "all sides. Your motto translates as \"patience cuts deeper " &
      "than blades.\" Other houses consider you untrustworthy, but " &
      "indispensable."
  ),
  (
    tag: "marius",
    blurb: "A martial dynasty that has produced more fleet admirals " &
      "than any other house. Your officers duel for command " &
      "positions. Your war college is considered the finest in " &
      "known space."
  ),
  (
    tag: "kalan",
    blurb: "Merchant princes who built their fortune on monopolizing " &
      "rare earth extraction in the Kalan Cluster. Every marriage " &
      "into another house carries financial arrangements that " &
      "benefit Kalan interests for generations."
  ),
  (
    tag: "delos",
    blurb: "Founded by a legendary scientist-explorer who discovered " &
      "the Delos Traverse. Your house maintains an obsession with " &
      "technological superiority and views the other houses as " &
      "provincial."
  ),
  (
    tag: "stratos",
    blurb: "You have conquered and absorbed three lesser houses in " &
      "the past two centuries through strategic marriages and " &
      "opportunistic invasions. You celebrate Incorporation Day " &
      "annually."
  ),
  (
    tag: "nikos",
    blurb: "Known for internal power struggles that sometimes spill " &
      "into open civil war between family branches. Despite chronic " &
      "instability, you have held your core territories for eight " &
      "centuries through sheer stubbornness."
  ),
  (
    tag: "hektor",
    blurb: "Your ancestral homeworld was rendered uninhabitable three " &
      "centuries ago by industrial collapse. Now scattered across " &
      "multiple systems, Hektor gatherings are melancholic affairs " &
      "focused on lost glory and eventual restoration."
  ),
  (
    tag: "krios",
    blurb: "You began as frontier colonists who struck it rich finding " &
      "habitable worlds in what others considered worthless space. " &
      "You still maintain a frontier mentality and look down on the " &
      "soft core-world houses."
  ),
  (
    tag: "zenos",
    blurb: "Every generation produces one designated Philosopher-Heir " &
      "who writes official history and strategic doctrine. These " &
      "texts are studied throughout the empire, giving your house " &
      "outsized cultural influence despite modest military power."
  ),
  (
    tag: "theron",
    blurb: "You have survived five major invasions by trading space " &
      "for time and bleeding attackers dry. Your commanders are " &
      "legendarily cautious, earning a reputation for patience " &
      "among more aggressive houses."
  ),
  (
    tag: "alexos",
    blurb: "The newest great house, elevated only three generations " &
      "ago through a marriage alliance. The older dynatoi still " &
      "treat you as upstarts—which you take as a personal insult " &
      "requiring constant proof of legitimacy."
  ),
]

# =============================================================================
# Helpers
# =============================================================================

import std/strutils

proc houseLoreBlurb(houseName: string): string =
  ## Look up lore blurb by matching house name (case-insensitive).
  ## Falls back to a generic blurb if not found.
  let lower = houseName.toLowerAscii()
  for entry in HouseLoreTable:
    if lower.contains(entry.tag):
      return entry.blurb
  "Your house has endured the long centuries since the First " &
    "Expansion. Now, a new age of conquest begins."

# =============================================================================
# Report Builders
# =============================================================================

proc generateIntroReport(
    houseName: string,
    turn: int
): ReportEntry =
  ## Build the Turn 1 welcome/intro report for the given house.
  let lore = houseLoreBlurb(houseName)
  ReportEntry(
    id: 1,
    turn: turn,
    category: ReportCategory.Summary,
    title: "Welcome to EC4X — House " & houseName,
    summary: "The age of conquest begins. Your house awaits " &
      "your command.",
    detail: @[
      "=== YOUR HOUSE ===",
      lore,
      "",
      "=== VICTORY CONDITION: PRESTIGE ===",
      "EC4X is a zero-sum prestige race. Military victories, " &
        "planetary conquests, economic growth, and technological " &
        "advancement all elevate your standing.",
      "Losing a colony to an enemy carries a severe prestige " &
        "penalty—never leave colonies undefended.",
      "",
      "=== EARLY EXPANSION: ETACs ===",
      "You begin with 2 ETAC fleets. Each ETAC carries 3 PTU " &
        "of frozen colonists, enough to plant a foundation colony " &
        "with a 3 PU starter population.",
      "ETACs are consumed on landing—the ship itself becomes " &
        "the colony's starting infrastructure.",
      "Crucially, ETAC fleets do NOT count against your " &
        "Strategic Command (SC) fleet limit. Use them freely " &
        "for early land grabs before rivals claim the best " &
        "systems.",
      "",
      "=== EXPLORATION: SCOUTS ===",
      "Scouts are fast, carry no cargo, and cost zero Command " &
        "Cost (CC). Send them ahead of your expansion wave to " &
        "uncover the fog of war and identify high-value systems " &
        "before committing your ETACs.",
      "Intel decays over time. Maintain scout patrols on " &
        "your borders to track rival fleet movements.",
    ],
    isUnread: true,
    linkView: 1,
    linkLabel: "Overview",
  )

# =============================================================================
# Public API
# =============================================================================

proc generateClientReports*(
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate the full client-side report list from PlayerState.
  ##
  ## On turn 1 (game start) this prepends a welcome/intro report
  ## containing House lore, Prestige objectives, and ETAC/Scout hints.
  ## Additional report generators can be appended here as the feature
  ## grows (e.g. income summary, combat debriefs).
  result = @[]
  if ps.turn <= 1:
    let houseName =
      ps.houseNames.getOrDefault(ps.viewingHouse, "Unknown")
    result.add(generateIntroReport(houseName, ps.turn))
