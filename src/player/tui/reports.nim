## Client-side turn report generator
##
## The engine does not generate narrative reports (per intel.md
## architecture decision: engine = data, client = presentation).
## This module interprets PlayerState snapshots to produce
## human-readable ReportEntry items for the inbox/reports view.
##
## Generates:
##   - Turn 1 welcome/intro report with House lore and hints.
##   - Diff-based reports from comparing current and prev PlayerState:
##       Colony events (founded, lost, blockaded, terraformed)
##       Fleet events (formed, destroyed)
##       Ship events (commissioned, lost, crippled, repaired)
##       Intel events (enemy fleets detected/departed, colonies
##         discovered, systems surveyed)
##       Staleness alerts (intel older than 3 turns)
##       Diplomacy events (relation changes, eliminations, acts)
##       Economy events (prestige, tech advances, treasury deficit)
##       Turn summary (overview stats and idle fleet alerts)

import std/[tables, options, sets, strutils, algorithm, sequtils]
import ../../engine/types/[
  core, colony, fleet, ship,
  player_state as ps_types,
  diplomacy, progression, combat, tech, event
]
import ../sam/tui_model

# =============================================================================
# Report ID Generation
# =============================================================================

var nextReportId {.global.} = 100
  ## Global counter; reset each generateClientReports call.
  ## Starts at 100 to avoid collision with intro report (id=1).

proc nextId(): int =
  result = nextReportId
  inc nextReportId

# =============================================================================
# House Lore Table
# =============================================================================

type HouseLore = tuple[tag: string, blurb: string]

const HouseLoreTable: array[12, HouseLore] = [
  (
    tag: "valerian",
    blurb: "The Valerian dynasty measures its age not in generations " &
      "but in stellar epochs. When the First Expansion pushed " &
      "humanity beyond the core systems, it was a Valerian who " &
      "planted the first flag on a world orbiting another star — " &
      "a fact your archivists have never allowed anyone to forget.\n" &
      "\n" &
      "Your ancestral seat orbits a dying red giant, a calculated " &
      "choice made by your founders: every heir who gazes upon " &
      "that swelling, cooling star is reminded that nothing lasts " &
      "forever except the will to endure. You are the oldest of " &
      "the dynatoi. The other houses know it. So do you."
  ),
  (
    tag: "thelon",
    blurb: "The Thelon rose to prominence not through conquest or " &
      "discovery, but through something rarer and more durable: " &
      "patience. During the Collapse Wars, when every other house " &
      "chose a side and bled for it, you chose all of them — " &
      "supplying, informing, and quietly profiting while the " &
      "great fleets destroyed one another.\n" &
      "\n" &
      "Your motto translates loosely as \"patience cuts deeper " &
      "than blades.\" The other houses have never forgiven you " &
      "for being right. They call you treacherous in the same " &
      "breath they call you indispensable, and you have long " &
      "understood that this contradiction is the source of all " &
      "your power."
  ),
  (
    tag: "marius",
    blurb: "There is an old saying in the officer academies: a " &
      "Marius never asks permission to fight, only where. Your " &
      "dynasty has produced more fleet admirals than any other " &
      "house in the empire — not by accident, but by design. " &
      "Command is earned through the duel here, not inherited " &
      "through appointment.\n" &
      "\n" &
      "Your war college draws candidates from across known space, " &
      "and graduates who wash out still outperform the best " &
      "officers most houses can field. You do not merely study " &
      "war. You have made war into a civilization."
  ),
  (
    tag: "kalan",
    blurb: "Wealth, your founders understood, is not gold or ships " &
      "or colonies. Wealth is the thing others cannot do without. " &
      "Three centuries ago, Kalan prospectors surveying what every " &
      "other house had dismissed as worthless rock discovered the " &
      "rare-earth deposits that power every drive coil, every " &
      "weapons array, every communications relay in the empire.\n" &
      "\n" &
      "You have been careful never to extract too much, never to " &
      "let prices fall, never to let a rival develop a substitute. " &
      "Every marriage contract your house signs contains financial " &
      "clauses that will still be generating revenue when the " &
      "grandchildren of the signatories are dust. The other houses " &
      "call this greed. You call it foresight."
  ),
  (
    tag: "delos",
    blurb: "The Delos Traverse — that improbable chain of stable " &
      "jump points threading through the Periphery — was not " &
      "discovered by accident. It was found by your founder, a " &
      "scientist-explorer who spent eleven years mapping " &
      "gravitational anomalies that every other navigator had " &
      "discarded as noise. The empire was built on that route, " &
      "and your house has never let it forget the debt.\n" &
      "\n" &
      "Technology is not merely a tool to House Delos; it is a " &
      "theology. You regard the other houses with a detached, " &
      "almost clinical pity — powerful in the way that blunt " &
      "instruments are powerful, incapable of the precision that " &
      "separates civilization from mere survival."
  ),
  (
    tag: "stratos",
    blurb: "Three houses no longer exist because of you. Not " &
      "destroyed in battle — absorbed, dissolved, their lineages " &
      "folded into yours through a combination of strategic " &
      "marriage and, when patience ran out, swift military action. " &
      "You celebrate Incorporation Day each year with a feast that " &
      "the surviving dynatoi attend and pretend to enjoy.\n" &
      "\n" &
      "Your expansion model is simple: identify a weaker neighbor, " &
      "cultivate dependency, then offer a merger that is more " &
      "politely worded than an ultimatum but functionally " &
      "indistinguishable from one. The empire considers you " &
      "aggressive. You consider yourself efficient."
  ),
  (
    tag: "nikos",
    blurb: "No house has torn itself apart as many times as Nikos " &
      "and still held its borders. The family tree splits at " &
      "nearly every generation into rival branches, and the " &
      "arguments over succession have twice erupted into open " &
      "civil war that the other houses watched with poorly " &
      "concealed delight. Both times, you survived.\n" &
      "\n" &
      "The historians explain this as stubbornness. Your own " &
      "strategists describe it differently: when a Nikos is " &
      "threatened from outside, the internal factions stop " &
      "fighting each other with a speed that has surprised more " &
      "than one invader. Eight centuries of core territory, " &
      "intact. The price was high, but the account remains open."
  ),
  (
    tag: "hektor",
    blurb: "Your homeworld is a cautionary tale taught in every " &
      "colonial engineering program in the empire. Three hundred " &
      "years ago, the industrial ambition of your ancestors " &
      "outpaced their caution, and the cascading ecological " &
      "collapse that followed rendered an entire planet " &
      "uninhabitable within a single generation. The Hektor " &
      "diaspora scattered across seven systems, carrying nothing " &
      "but memory and the burning need to rebuild.\n" &
      "\n" &
      "That wound has never closed. Your gatherings are quiet, " &
      "deliberate affairs, heavy with a shared understanding of " &
      "what was lost and what must never be risked again. Some " &
      "houses see tragedy in this. You see clarity. You know " &
      "precisely what is worth protecting — because you have " &
      "already lost it once."
  ),
  (
    tag: "krios",
    blurb: "The core-world houses still tell the story with a " &
      "mixture of amusement and discomfort: a convoy of " &
      "underfunded frontier colonists, turned away from every " &
      "catalogued system, pushed deeper into unmapped space out " &
      "of desperation — and found paradise. Not once, but four " &
      "times. The habitable worlds that built the Krios fortune " &
      "were sitting in sectors that three major survey expeditions " &
      "had written off as barren.\n" &
      "\n" &
      "You have never quite forgiven the core houses for their " &
      "condescension, and you have never quite stopped enjoying " &
      "the look on their faces when they need something only you " &
      "can provide. The frontier made you, and you see no reason " &
      "to pretend otherwise."
  ),
  (
    tag: "zenos",
    blurb: "Every generation, one member of the Zenos bloodline is " &
      "designated Philosopher-Heir and given a single mandate: " &
      "observe everything, write it down, and make it mean " &
      "something. The resulting texts — part history, part " &
      "strategic doctrine, part philosophy — are studied in " &
      "academies across the empire, and have shaped military " &
      "thinking for two centuries in ways that most commanders " &
      "cannot trace back to their source.\n" &
      "\n" &
      "This is power of a particular kind: invisible, deniable, " &
      "and almost impossible to destroy. Your fleets are modest. " &
      "Your armies are adequate. But the frameworks through which " &
      "your rivals understand the galaxy were, in significant " &
      "part, written by your ancestors. You find this deeply " &
      "satisfying."
  ),
  (
    tag: "theron",
    blurb: "Five times in three centuries, an invading force has " &
      "crossed into Theron space expecting a short campaign. " &
      "Five times, they encountered the same maddening response: " &
      "no decisive engagement, no fixed front, just a slow " &
      "grinding retreat that traded territory for time while " &
      "supply lines stretched thin and casualty lists grew longer " &
      "than any pre-war estimate had projected. Five times, the " &
      "invader eventually stopped.\n" &
      "\n" &
      "Your commanders are called cautious by rivals who confuse " &
      "aggression with competence. What they practice is something " &
      "more precise — an understanding that space is not a " &
      "weakness to yield, but a weapon to deploy. The patient " &
      "mind, your doctrine holds, wins the war that the impatient " &
      "mind wins on paper."
  ),
  (
    tag: "alexos",
    blurb: "Three generations ago, a marriage alliance elevated " &
      "what had been a prosperous but minor clan into the ranks " &
      "of the great houses. The ceremony was lavish. The " &
      "congratulations from the older dynatoi were gracious. " &
      "The tone behind both has never quite changed.\n" &
      "\n" &
      "You have spent three generations proving that your " &
      "elevation was earned and not merely granted, and the " &
      "oldest houses have spent three generations making sure " &
      "the standard of proof keeps rising. It has made you " &
      "formidable in ways your critics did not anticipate. " &
      "There is no more dangerous rival than one who has spent " &
      "their entire existence being told they do not belong."
  ),
]

# =============================================================================
# Helpers
# =============================================================================

proc houseLoreBlurb(houseName: string): string =
  ## Look up lore blurb by house name (case-insensitive).
  ## Falls back to a generic blurb if not found.
  let lower = houseName.toLowerAscii()
  for entry in HouseLoreTable:
    if lower.contains(entry.tag):
      return entry.blurb
  "Your house has endured the long centuries since the First " &
    "Expansion. Now, a new age of conquest begins."

proc sysLabel(
    systems: Table[SystemId, ps_types.VisibleSystem],
    sysId: SystemId
): string =
  ## Return system name or "System <id>" fallback.
  let name = systems.getOrDefault(sysId).name
  if name.len > 0: name else: "System " & $sysId

proc houseName(
    names: Table[HouseId, string],
    houseId: HouseId
): string =
  ## Return house name or "Unknown" fallback.
  names.getOrDefault(houseId, "Unknown")

# =============================================================================
# Generic Entity Diff Helper
# =============================================================================

proc diffIds[T, ID](
    prev: seq[T],
    curr: seq[T],
    getId: proc(e: T): ID {.closure.}
): tuple[
  added: seq[T],
  removed: seq[T],
  kept: seq[tuple[p: T, c: T]]
] =
  ## Compare two sequences by entity ID.
  ## Returns added (in curr not in prev), removed (in prev not
  ## in curr), and kept (present in both, as (prev, curr) pairs).
  var prevMap: Table[ID, T]
  var currMap: Table[ID, T]
  for e in prev: prevMap[getId(e)] = e
  for e in curr: currMap[getId(e)] = e
  var prevIds: HashSet[ID]
  var currIds: HashSet[ID]
  for id in prevMap.keys: prevIds.incl(id)
  for id in currMap.keys: currIds.incl(id)
  for id in (currIds - prevIds):
    result.added.add(currMap[id])
  for id in (prevIds - currIds):
    result.removed.add(prevMap[id])
  for id in (prevIds * currIds):
    result.kept.add((prevMap[id], currMap[id]))

# =============================================================================
# Report Builders: Intro
# =============================================================================

proc generateIntroReport(
    houseName: string,
    turn: int
): ReportEntry =
  ## Build the Turn 1 welcome/intro report for the given house.
  let lore = houseLoreBlurb(houseName)
  var detail: seq[string] = @["=== YOUR HOUSE ==="]
  for paragraph in lore.split('\n'):
    detail.add(paragraph)
  detail.add("")
  ReportEntry(
    id: 1,
    turn: turn,
    category: ReportCategory.Summary,
    title: "Welcome to EC4X — House " & houseName,
    summary: "The age of conquest begins. Your house awaits " &
      "your command.",
    detail: detail & @[
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
# Report Builders: Diff-Based
# =============================================================================

proc generateColonyReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on changes to own colonies between turns.
  result = @[]
  let diff = diffIds(
    prev.ownColonies,
    curr.ownColonies,
    proc(c: Colony): ColonyId = c.id
  )

  for colony in diff.added:
    let sname = sysLabel(
      curr.visibleSystems, colony.systemId)
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Operations,
      title: "Colony Established — " & sname,
      summary: "A new colony has been founded.",
      detail: @[
        "System: " & sname,
        "Population: " & $colony.population & " PU",
      ],
      isUnread: true,
      linkView: 2, linkLabel: "Planets",
    ))

  for colony in diff.removed:
    let sname = sysLabel(
      prev.visibleSystems, colony.systemId)
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Combat,
      title: "Colony Lost — " & sname,
      summary: "Your colony has fallen.",
      detail: @[
        "System: " & sname,
        "The colony is no longer under your control.",
      ],
      isUnread: true,
      linkView: 2, linkLabel: "Planets",
    ))

  for pair in diff.kept:
    let prevCol = pair.p
    let currCol = pair.c
    let sname = sysLabel(
      curr.visibleSystems, currCol.systemId)

    if not prevCol.blockaded and currCol.blockaded:
      var blockaderParts: seq[string] = @[]
      for bId in currCol.blockadedBy:
        blockaderParts.add(
          "House " & houseName(curr.houseNames, bId))
      let blockaderStr =
        if blockaderParts.len > 0:
          blockaderParts.join(", ")
        else: "Unknown forces"
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Combat,
        title: "Colony Blockaded — " & sname,
        summary: "Enemy forces have blockaded your colony.",
        detail: @[
          "System: " & sname,
          "Blockaded by: " & blockaderStr,
        ],
        isUnread: true,
        linkView: 2, linkLabel: "Planets",
      ))
    elif prevCol.blockaded and not currCol.blockaded:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Operations,
        title: "Blockade Lifted — " & sname,
        summary: "Trade routes have been restored.",
        detail: @["System: " & sname],
        isUnread: true,
        linkView: 2, linkLabel: "Planets",
      ))

    if prevCol.activeTerraforming.isSome and
        currCol.activeTerraforming.isNone:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Operations,
        title: "Terraforming Complete — " & sname,
        summary: "Terraforming project has completed.",
        detail: @["System: " & sname],
        isUnread: true,
        linkView: 2, linkLabel: "Planets",
      ))

proc generateFleetReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on changes to own fleets between turns.
  result = @[]
  let diff = diffIds(
    prev.ownFleets,
    curr.ownFleets,
    proc(f: Fleet): FleetId = f.id
  )

  for fleet in diff.removed:
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Combat,
      title: "Fleet Lost — " & fleet.name,
      summary: "Fleet " & fleet.name &
        " has been destroyed.",
      detail: @[
        "Fleet " & fleet.name & " with " &
          $fleet.ships.len &
          " ships is no longer operational.",
      ],
      isUnread: true,
      linkView: 3, linkLabel: "Fleets",
    ))

  for fleet in diff.added:
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Operations,
      title: "Fleet Formed — " & fleet.name,
      summary: "A new fleet has been organized.",
      detail: @[
        "Fleet " & fleet.name & " with " &
          $fleet.ships.len & " ships.",
      ],
      isUnread: true,
      linkView: 3, linkLabel: "Fleets",
    ))

proc generateShipReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on ship commissioning, losses, and state changes.
  ## Ships of the same class are batched into a single report
  ## to avoid inbox spam.
  result = @[]
  let diff = diffIds(
    prev.ownShips,
    curr.ownShips,
    proc(s: Ship): ShipId = s.id
  )

  var newByClass: Table[ShipClass, int]
  for ship in diff.added:
    newByClass.mgetOrPut(ship.shipClass, 0) += 1
  for cls, count in newByClass.pairs:
    let plural = if count > 1: "s" else: ""
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Operations,
      title: $count & " " & $cls & plural &
        " Commissioned",
      summary: $count & " new " & $cls & plural &
        " entered service.",
      detail: @[
        $count & " " & $cls & plural &
          " have been commissioned.",
      ],
      isUnread: true,
      linkView: 3, linkLabel: "Fleets",
    ))

  var lostByClass: Table[ShipClass, int]
  for ship in diff.removed:
    lostByClass.mgetOrPut(ship.shipClass, 0) += 1
  for cls, count in lostByClass.pairs:
    let plural = if count > 1: "s" else: ""
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Combat,
      title: $count & " " & $cls & plural & " Lost",
      summary: $count & " " & $cls & plural &
        " have been destroyed.",
      detail: @[
        $count & " " & $cls & plural & " lost.",
      ],
      isUnread: true,
      linkView: 3, linkLabel: "Fleets",
    ))

  for pair in diff.kept:
    let ps = pair.p
    let cs = pair.c
    if ps.state == CombatState.Nominal and
        cs.state == CombatState.Crippled:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Combat,
        title: $cs.shipClass & " Crippled",
        summary: "A " & $cs.shipClass &
          " has been crippled in combat.",
        detail: @["Ship class: " & $cs.shipClass],
        isUnread: true,
        linkView: 3, linkLabel: "Fleets",
      ))
    elif ps.state == CombatState.Crippled and
        cs.state == CombatState.Nominal:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Operations,
        title: $cs.shipClass & " Repaired",
        summary: "A " & $cs.shipClass &
          " has been fully repaired.",
        detail: @["Ship class: " & $cs.shipClass],
        isUnread: true,
        linkView: 3, linkLabel: "Fleets",
      ))

proc generateIntelReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on enemy fleet/colony detection and system surveys.
  result = @[]

  let fleetDiff = diffIds(
    prev.visibleFleets,
    curr.visibleFleets,
    proc(f: ps_types.VisibleFleet): FleetId = f.fleetId
  )
  for fleet in fleetDiff.added:
    let sname = sysLabel(
      curr.visibleSystems, fleet.location)
    let oname = houseName(curr.houseNames, fleet.owner)
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Intelligence,
      title: "Enemy Fleet Detected — " & sname,
      summary: "House " & oname &
        " fleet detected in " & sname & ".",
      detail: @[
        "Owner: House " & oname,
        "Location: " & sname,
      ],
      isUnread: true,
      linkView: 8, linkLabel: "Intel",
    ))
  for fleet in fleetDiff.removed:
    let sname = sysLabel(
      prev.visibleSystems, fleet.location)
    let oname = houseName(curr.houseNames, fleet.owner)
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Intelligence,
      title: "Enemy Fleet Departed — " & sname,
      summary: "House " & oname &
        " fleet no longer detected.",
      detail: @[
        "Owner: House " & oname,
        "Last known location: " & sname,
      ],
      isUnread: true,
      linkView: 8, linkLabel: "Intel",
    ))

  let colDiff = diffIds(
    prev.visibleColonies,
    curr.visibleColonies,
    proc(c: ps_types.VisibleColony): ColonyId =
      c.colonyId
  )
  for col in colDiff.added:
    let sname = sysLabel(
      curr.visibleSystems, col.systemId)
    let oname = houseName(curr.houseNames, col.owner)
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Intelligence,
      title: "Enemy Colony Discovered — " & sname,
      summary: "House " & oname &
        " colony detected in " & sname & ".",
      detail: @[
        "Owner: House " & oname,
        "System: " & sname,
      ],
      isUnread: true,
      linkView: 8, linkLabel: "Intel",
    ))

  # Newly visible or upgraded systems
  for sysId, currSys in curr.visibleSystems.pairs:
    if sysId notin prev.visibleSystems:
      if currSys.visibility >=
          ps_types.VisibilityLevel.Scouted:
        result.add(ReportEntry(
          id: nextId(), turn: int(curr.turn),
          category: ReportCategory.Intelligence,
          title: "System Surveyed — " & currSys.name,
          summary: "Your scouts have surveyed " &
            currSys.name & ".",
          detail: @[
            "System: " & currSys.name,
            "Planet Class: " & $currSys.planetClass,
            "Resource Rating: " &
              $currSys.resourceRating,
          ],
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))
    else:
      let prevVis =
        prev.visibleSystems[sysId].visibility
      let currVis = currSys.visibility
      # Upgraded from Adjacent-only to Scouted+
      if prevVis < ps_types.VisibilityLevel.Scouted and
          currVis >= ps_types.VisibilityLevel.Scouted:
        result.add(ReportEntry(
          id: nextId(), turn: int(curr.turn),
          category: ReportCategory.Intelligence,
          title: "System Surveyed — " & currSys.name,
          summary: currSys.name &
            " has been explored by your scouts.",
          detail: @[
            "System: " & currSys.name,
            "Planet Class: " & $currSys.planetClass,
            "Resource Rating: " &
              $currSys.resourceRating,
          ],
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))

proc generateStalenessAlerts(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Advisory alerts for intel older than 3 turns.
  ## Per spec 9.11 and docs/architecture/intel.md.
  ## These are non-urgent (isUnread: false).
  result = @[]
  const staleThreshold = 3

  for fleetId, ltu in curr.ltuFleets.pairs:
    let age = int(curr.turn) - int(ltu)
    if age > staleThreshold:
      var sname = ""
      var oname = ""
      for vf in curr.visibleFleets:
        if vf.fleetId == fleetId:
          sname = sysLabel(
            curr.visibleSystems, vf.location)
          oname = houseName(
            curr.houseNames, vf.owner)
          break
      if sname.len == 0:
        continue
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Intelligence,
        title: "Intel Stale — Fleet in " & sname,
        summary: "Fleet sighting in " & sname &
          " is " & $age & " turns old.",
        detail: @[
          "Owner: House " & oname,
          "Last seen: Turn " & $ltu,
          "Age: " & $age & " turns",
          "Fleet may have moved.",
        ],
        isUnread: false,
        linkView: 8, linkLabel: "Intel",
      ))

  for colId, ltu in curr.ltuColonies.pairs:
    let age = int(curr.turn) - int(ltu)
    if age > staleThreshold:
      var sname = ""
      var oname = ""
      for vc in curr.visibleColonies:
        if vc.colonyId == colId:
          sname = sysLabel(
            curr.visibleSystems, vc.systemId)
          oname = houseName(
            curr.houseNames, vc.owner)
          break
      if sname.len == 0:
        continue
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Intelligence,
        title: "Intel Stale — Colony in " & sname,
        summary: "Colony intel for " & sname &
          " is " & $age & " turns old.",
        detail: @[
          "Owner: House " & oname,
          "Last scouted: Turn " & $ltu,
          "Age: " & $age & " turns",
          "Data may no longer reflect reality.",
        ],
        isUnread: false,
        linkView: 8, linkLabel: "Intel",
      ))

proc generateDiplomacyReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on diplomatic relation changes, house eliminations,
  ## and act transitions.
  result = @[]
  let us = curr.viewingHouse

  for pair, newState in curr.diplomaticRelations.pairs:
    let (h1, h2) = pair
    if h1 != us and h2 != us:
      continue
    let them = if h1 == us: h2 else: h1
    let tname = houseName(curr.houseNames, them)
    let oldState =
      prev.diplomaticRelations.getOrDefault(
        pair, DiplomaticState.Neutral)
    if oldState != newState:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Diplomacy,
        title: "Diplomatic Change — House " & tname,
        summary: "Relations with House " & tname &
          " changed from " & $oldState &
          " to " & $newState & ".",
        detail: @[
          "House: " & tname,
          "Previous: " & $oldState,
          "Current: " & $newState,
        ],
        isUnread: true,
        linkView: 6, linkLabel: "Economy",
      ))

  let prevElim = prev.eliminatedHouses.toHashSet()
  for houseId in curr.eliminatedHouses:
    if houseId notin prevElim:
      let ename = houseName(curr.houseNames, houseId)
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Diplomacy,
        title: "House Eliminated — " & ename,
        summary: "House " & ename &
          " has been eliminated from the game.",
        detail: @["House " & ename & " is no more."],
        isUnread: true,
        linkView: 1, linkLabel: "Overview",
      ))

  if prev.actProgression.currentAct !=
      curr.actProgression.currentAct:
    let actName =
      case curr.actProgression.currentAct
      of GameAct.Act1_LandGrab:
        "Act I — Land Grab"
      of GameAct.Act2_RisingTensions:
        "Act II — Rising Tensions"
      of GameAct.Act3_TotalWar:
        "Act III — Total War"
      of GameAct.Act4_Endgame:
        "Act IV — Endgame"
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Diplomacy,
      title: "New Era — " & actName,
      summary: "The game has entered " & actName & ".",
      detail: @[
        "Strategic priorities have shifted.",
        actName & " begins on turn " &
          $curr.turn & ".",
      ],
      isUnread: true,
      linkView: 1, linkLabel: "Overview",
    ))

proc generateEconomyReports(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Reports on prestige changes, tech advances, and treasury
  ## deficits.
  result = @[]
  let us = curr.viewingHouse

  let oldPrestige =
    prev.housePrestige.getOrDefault(us, 0)
  let newPrestige =
    curr.housePrestige.getOrDefault(us, 0)
  if oldPrestige != newPrestige:
    let delta = newPrestige - oldPrestige
    let direction =
      if delta > 0: "+" & $delta else: $delta
    result.add(ReportEntry(
      id: nextId(), turn: int(curr.turn),
      category: ReportCategory.Economy,
      title: "Prestige Update",
      summary: "Prestige changed by " & direction &
        " (now " & $newPrestige & ").",
      detail: @[
        "Previous: " & $oldPrestige,
        "Current: " & $newPrestige,
        "Change: " & direction,
      ],
      isUnread: true,
      linkView: 1, linkLabel: "Overview",
    ))

  if prev.techLevels.isSome and
      curr.techLevels.isSome:
    let ot = prev.techLevels.get()
    let nt = curr.techLevels.get()
    template checkTech(
        fname: string,
        oldVal, newVal: int32) =
      if newVal > oldVal:
        result.add(ReportEntry(
          id: nextId(), turn: int(curr.turn),
          category: ReportCategory.Economy,
          title: "Technology Advance — " & fname,
          summary: fname &
            " advanced to level " & $newVal & ".",
          detail: @[
            fname & ": " & $oldVal &
              " -> " & $newVal,
          ],
          isUnread: true,
          linkView: 4, linkLabel: "Research",
        ))
    checkTech("Economic Level", ot.el, nt.el)
    checkTech("Science Level", ot.sl, nt.sl)
    checkTech("Construction Tech", ot.cst, nt.cst)
    checkTech("Weapons Tech", ot.wep, nt.wep)
    checkTech("Terraforming Tech", ot.ter, nt.ter)
    checkTech("Electronic Intelligence",
      ot.eli, nt.eli)
    checkTech("Cloaking Tech", ot.clk, nt.clk)
    checkTech("Shield Tech", ot.sld, nt.sld)
    checkTech("Counter Intelligence",
      ot.cic, nt.cic)
    checkTech("Strategic Lift", ot.stl, nt.stl)
    checkTech("Flagship Command", ot.fc, nt.fc)
    checkTech("Strategic Command", ot.sc, nt.sc)
    checkTech("Fighter Doctrine", ot.fd, nt.fd)
    checkTech("Advanced Carrier Ops",
      ot.aco, nt.aco)

  if curr.treasuryBalance.isSome:
    let bal = curr.treasuryBalance.get()
    if bal < 0:
      result.add(ReportEntry(
        id: nextId(), turn: int(curr.turn),
        category: ReportCategory.Economy,
        title: "Treasury Deficit",
        summary: "Your treasury is in deficit (" &
          $bal & " RU).",
        detail: @[
          "Balance: " & $bal & " RU",
          "Fleets may be disbanded to cover " &
            "shortfalls.",
        ],
        isUnread: true,
        linkView: 1, linkLabel: "Overview",
      ))

proc generateTurnSummary(
    prev, curr: ps_types.PlayerState
): seq[ReportEntry] =
  ## Single summary report with overview stats and idle alerts.
  result = @[]
  let us = curr.viewingHouse
  var lines: seq[string] = @[]

  lines.add("Colonies: " & $curr.ownColonies.len)

  let activeFleets = curr.ownFleets.filterIt(
    it.status == FleetStatus.Active).len
  lines.add("Active Fleets: " & $activeFleets)
  lines.add("Ships: " & $curr.ownShips.len)

  if curr.treasuryBalance.isSome:
    lines.add("Treasury: " &
      $curr.treasuryBalance.get() & " RU")
  if curr.netIncome.isSome:
    lines.add("Net Income: " &
      $curr.netIncome.get() & " RU/turn")

  let prestige =
    curr.housePrestige.getOrDefault(us, 0)
  lines.add("Prestige: " & $prestige)

  var allPrestige: seq[tuple[p: int32, h: HouseId]]
  for hId, p in curr.housePrestige.pairs:
    allPrestige.add((p, hId))
  allPrestige.sort(
    proc(a, b: tuple[p: int32, h: HouseId]): int =
      cmp(b.p, a.p)
  )
  var rank = 1
  for entry in allPrestige:
    if entry.h == us: break
    inc rank
  lines.add("Prestige Rank: " & $rank &
    " of " & $allPrestige.len)

  var idleCount = 0
  for fleet in curr.ownFleets:
    if fleet.command.commandType ==
        FleetCommandType.Hold and
        fleet.status == FleetStatus.Active:
      inc idleCount
  if idleCount > 0:
    lines.add("")
    lines.add("ALERT: " & $idleCount &
      " fleet(s) on Hold with no orders.")

  result.add(ReportEntry(
    id: nextId(), turn: int(curr.turn),
    category: ReportCategory.Summary,
    title: "Turn " & $curr.turn & " Summary",
    summary: $curr.ownColonies.len &
      " colonies, " & $activeFleets &
      " fleets, prestige " & $prestige,
    detail: lines,
    isUnread: true,
    linkView: 1, linkLabel: "Overview",
  ))

# =============================================================================
# Event-Based Report Generators (Phase 2)
# =============================================================================

proc generateCombatReports(
    events: seq[GameEvent],
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate reports from high-priority combat events.
  result = @[]
  let us = ps.viewingHouse
  for evt in events:
    case evt.eventType
    of GameEventType.CombatResult:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      let outcomeStr = evt.outcome.get("Unknown")
      var lines: seq[string] = @[
        "System: " & sysName,
        "Outcome: " & outcomeStr,
      ]
      if evt.attackerLosses.isSome:
        lines.add("Attacker losses: " &
          $evt.attackerLosses.get())
      if evt.defenderLosses.isSome:
        lines.add("Defender losses: " &
          $evt.defenderLosses.get())
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Battle — " & sysName,
        summary: "Combat resolved: " & outcomeStr,
        detail: lines,
        isUnread: true,
        linkView: 2, linkLabel: "Starmap",
      ))
    of GameEventType.SystemCaptured:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "System Captured — " & sysName,
        summary: evt.description,
        detail: @[evt.description],
        isUnread: true,
        linkView: 2, linkLabel: "Starmap",
      ))
    of GameEventType.ColonyCaptured:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Colony Captured — " & sysName,
        summary: evt.description,
        detail: @[evt.description],
        isUnread: true,
        linkView: 3, linkLabel: "Planets",
      ))
    of GameEventType.InvasionRepelled:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Invasion Repelled — " & sysName,
        summary: evt.description,
        detail: @[
          "System: " & sysName,
          evt.description,
        ],
        isUnread: true,
        linkView: 3, linkLabel: "Planets",
      ))
    of GameEventType.BlockadeSuccessful:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Blockade Established — " & sysName,
        summary: evt.description,
        detail: @[
          "System: " & sysName,
          evt.description,
        ],
        isUnread: true,
        linkView: 3, linkLabel: "Planets",
      ))
    of GameEventType.FleetDestroyed:
      let sysName =
        if evt.systemId.isSome:
          ps.visibleSystems.getOrDefault(
            evt.systemId.get()).name
        else: "Unknown System"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Fleet Destroyed — " & sysName,
        summary: evt.description,
        detail: @[
          "System: " & sysName,
          evt.description,
        ],
        isUnread: true,
        linkView: 4, linkLabel: "Fleets",
      ))
    of GameEventType.FleetEncounter:
      let sysName =
        if evt.encounterLocation.isSome:
          sysLabel(ps.visibleSystems,
            evt.encounterLocation.get())
        else: "Unknown System"
      var lines: seq[string] = @[
        "System: " & sysName,
      ]
      if evt.encounteringFleetId.isSome:
        lines.add("Fleet: " &
          $evt.encounteringFleetId.get())
      if evt.encounteredFleetIds.isSome:
        lines.add("Enemy fleets: " &
          $evt.encounteredFleetIds.get().len)
      if evt.diplomaticStatus.isSome:
        lines.add("Status: " &
          evt.diplomaticStatus.get())
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Combat,
        title: "Visual Contact — " & sysName,
        summary: evt.description,
        detail: lines,
        isUnread: true,
        linkView: 3, linkLabel: "Fleets",
      ))
    of GameEventType.StarbaseSurveillanceDetection:
      # Show only to the starbase owner
      if evt.surveillanceOwner == some(us):
        let sysName =
          if evt.systemId.isSome:
            sysLabel(ps.visibleSystems,
              evt.systemId.get())
          else: "Unknown System"
        var lines: seq[string] = @[
          "System: " & sysName,
        ]
        if evt.detectedFleetsCount.isSome:
          lines.add("Fleets detected: " &
            $evt.detectedFleetsCount.get())
        if evt.undetectedFleetsCount.isSome:
          lines.add("Fleets evaded: " &
            $evt.undetectedFleetsCount.get())
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Combat,
          title: "Starbase Early Warning — " & sysName,
          summary: evt.description,
          detail: lines,
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))
    of GameEventType.RaiderDetected:
      let sysName =
        if evt.systemId.isSome:
          sysLabel(ps.visibleSystems,
            evt.systemId.get())
        else: "Unknown System"
      let isRaiderOwner =
        evt.houseId == some(us)
      let isDetector =
        evt.detectorHouse == some(us)
      if isRaiderOwner:
        var lines: seq[string] = @[
          "System: " & sysName,
        ]
        if evt.detectorType.isSome:
          lines.add("Detected by: " &
            evt.detectorType.get())
        if evt.eliRoll.isSome:
          lines.add("ELI roll: " &
            $evt.eliRoll.get())
        if evt.clkRoll.isSome:
          lines.add("CLK roll: " &
            $evt.clkRoll.get())
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Combat,
          title: "Stealth Compromised — " & sysName,
          summary: "Your cloaked fleet was detected.",
          detail: lines,
          isUnread: true,
          linkView: 3, linkLabel: "Fleets",
        ))
      elif isDetector:
        var lines: seq[string] = @[
          "System: " & sysName,
        ]
        if evt.detectorType.isSome:
          lines.add("Detected by: " &
            evt.detectorType.get())
        if evt.eliRoll.isSome:
          lines.add("ELI roll: " &
            $evt.eliRoll.get())
        if evt.clkRoll.isSome:
          lines.add("CLK roll: " &
            $evt.clkRoll.get())
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Combat,
          title: "Cloaked Ships Detected — " & sysName,
          summary: "Enemy cloaked fleet detected " &
            "in " & sysName & ".",
          detail: lines,
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))
    of GameEventType.RaiderStealthSuccess:
      # Only visible to raider owner (silent success)
      if evt.houseId == some(us):
        let sysName =
          if evt.systemId.isSome:
            sysLabel(ps.visibleSystems,
              evt.systemId.get())
          else: "Unknown System"
        var lines: seq[string] = @[
          "System: " & sysName,
        ]
        if evt.attemptedDetectorType.isSome:
          lines.add("Evaded: " &
            evt.attemptedDetectorType.get())
        if evt.stealthEliRoll.isSome:
          lines.add("ELI roll: " &
            $evt.stealthEliRoll.get())
        if evt.stealthClkRoll.isSome:
          lines.add("CLK roll: " &
            $evt.stealthClkRoll.get())
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Combat,
          title: "Stealth Evaded Sensors — " &
            sysName,
          summary: "Your cloaked fleet evaded " &
            "enemy detection.",
          detail: lines,
          isUnread: true,
          linkView: 3, linkLabel: "Fleets",
        ))
    else:
      discard

proc generateEspionageReports(
    events: seq[GameEvent],
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate reports from espionage events.
  ##
  ## Generates dual-perspective narratives: the viewing house
  ## may be the attacker (sourceHouseId) or the defender
  ## (targetHouseId). Per game spec 9.3/9.5.5.
  result = @[]
  let us = ps.viewingHouse
  for evt in events:
    case evt.eventType
    of GameEventType.SpyMissionSucceeded,
        GameEventType.SabotageConducted,
        GameEventType.TechTheftExecuted,
        GameEventType.AssassinationAttempted,
        GameEventType.EconomicManipulationExecuted,
        GameEventType.CyberAttackConducted,
        GameEventType.SpyMissionDetected:
      let isAttacker =
        evt.sourceHouseId == some(us)
      let isDefender =
        evt.targetHouseId == some(us)
      if not isAttacker and not isDefender:
        continue
      let otherHouseId =
        if isAttacker: evt.targetHouseId
        else: evt.sourceHouseId
      let otherName =
        if otherHouseId.isSome:
          ps.houseNames.getOrDefault(
            otherHouseId.get(), "Unknown House")
        else: "Unknown House"
      let succeeded =
        evt.success.get(false)
      let detected =
        evt.detected.get(false)

      let (title, summary) =
        if isAttacker:
          if detected:
            ("Spy Mission Detected — " & otherName,
             "Your operation against House " &
               otherName &
               " was detected and failed.")
          elif succeeded:
            ("Spy Mission Succeeded — " & otherName,
             "Your operation against House " &
               otherName & " succeeded.")
          else:
            ("Spy Mission Failed — " & otherName,
             "Your operation against House " &
               otherName & " failed.")
        else: # isDefender
          if detected:
            ("Enemy Spy Caught — " & otherName,
             "House " & otherName &
               " attempted an operation — " &
               "detected and prevented.")
          else:
            ("Enemy Operation — " & otherName,
             "House " & otherName &
               " conducted a covert operation " &
               "against you.")

      var lines: seq[string] = @[]
      if evt.description.len > 0:
        lines.add(evt.description)
      if evt.details.isSome:
        lines.add(evt.details.get())
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Intelligence,
        title: title,
        summary: summary,
        detail: lines,
        isUnread: true,
        linkView: 6, linkLabel: "Espionage",
      ))
    of GameEventType.PsyopsCampaignLaunched:
      let isAttacker =
        evt.sourceHouseId == some(us)
      let isDefender =
        evt.targetHouseId == some(us)
      if isAttacker:
        let targetName =
          if evt.targetHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.targetHouseId.get(), "Unknown House")
          else: "Unknown House"
        let succeeded = evt.success.get(false)
        let statusStr =
          if succeeded: "Success" else: "Failure"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Propaganda Campaign — " & statusStr,
          summary: "Psyops campaign against House " &
            targetName & " " &
            (if succeeded: "succeeded." else: "failed."),
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
      elif isDefender and evt.detected.get(false):
        let attackerName =
          if evt.sourceHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.sourceHouseId.get(), "Unknown House")
          else: "Unknown House"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Enemy Propaganda Detected",
          summary: "House " & attackerName &
            " attempted propaganda against you.",
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
    of GameEventType.IntelTheftExecuted:
      let isAttacker =
        evt.sourceHouseId == some(us)
      let isDefender =
        evt.targetHouseId == some(us)
      if isAttacker:
        let targetName =
          if evt.targetHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.targetHouseId.get(), "Unknown House")
          else: "Unknown House"
        let succeeded = evt.success.get(false)
        let statusStr =
          if succeeded: "Succeeded" else: "Failed"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Intelligence Theft " & statusStr,
          summary: "Intel theft against House " &
            targetName & " " &
            (if succeeded: "succeeded." else: "failed."),
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
      elif isDefender and evt.detected.get(false):
        let attackerName =
          if evt.sourceHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.sourceHouseId.get(), "Unknown House")
          else: "Unknown House"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Cyber Intrusion Detected",
          summary: "House " & attackerName &
            " attempted to steal intelligence.",
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
    of GameEventType.DisinformationPlanted:
      let isAttacker =
        evt.sourceHouseId == some(us)
      let isDefender =
        evt.targetHouseId == some(us)
      if isAttacker:
        let targetName =
          if evt.targetHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.targetHouseId.get(), "Unknown House")
          else: "Unknown House"
        let succeeded = evt.success.get(false)
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: if succeeded: "Disinformation Planted"
                 else: "Disinformation Failed",
          summary: "Disinformation against House " &
            targetName & " " &
            (if succeeded: "planted." else: "failed."),
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
      elif isDefender and evt.detected.get(false):
        let attackerName =
          if evt.sourceHouseId.isSome:
            ps.houseNames.getOrDefault(
              evt.sourceHouseId.get(), "Unknown House")
          else: "Unknown House"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Disinformation Prevented",
          summary: "House " & attackerName &
            " attempted disinformation — detected.",
          detail: @[evt.description],
          isUnread: true,
          linkView: 6, linkLabel: "Espionage",
        ))
    of GameEventType.CounterIntelSweepExecuted:
      # Only report if we executed the sweep
      if evt.houseId == some(us):
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Operations,
          title: "Counter-Intelligence Sweep Active",
          summary: "Enemy intelligence gathering " &
            "blocked this turn.",
          detail: @[
            "Counter-Intelligence Sweep executed.",
            "Enemy scout reports and spy operations " &
              "are suppressed this turn.",
          ],
          isUnread: true,
          linkView: 1, linkLabel: "Overview",
        ))
    else:
      discard

proc generateCommandReports(
    events: seq[GameEvent],
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate reports from command rejection/failure events.
  result = @[]
  for evt in events:
    case evt.eventType
    of GameEventType.CommandCompleted:
      var lines: seq[string] = @[]
      if evt.orderType.isSome:
        lines.add("Order: " & evt.orderType.get())
      if evt.fleetId.isSome:
        lines.add("Fleet: " & $evt.fleetId.get())
      if evt.systemId.isSome:
        lines.add("System: " & sysLabel(
          ps.visibleSystems, evt.systemId.get()))
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Operations,
        title: "Command Completed — " &
          evt.orderType.get("Unknown"),
        summary: evt.description,
        detail: lines,
        isUnread: true,
        linkView: 3, linkLabel: "Fleets",
      ))
    of GameEventType.FleetArrived:
      let sysName =
        if evt.systemId.isSome:
          sysLabel(ps.visibleSystems, evt.systemId.get())
        else: "Unknown System"
      var lines: seq[string] = @[]
      if evt.fleetId.isSome:
        lines.add("Fleet: " & $evt.fleetId.get())
      lines.add("Destination: " & sysName)
      if evt.orderType.isSome:
        lines.add("Order: " & evt.orderType.get())
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Operations,
        title: "Fleet Arrived — " & sysName,
        summary: evt.description,
        detail: lines,
        isUnread: true,
        linkView: 3, linkLabel: "Fleets",
      ))
    of GameEventType.ColonyEstablished:
      # Event-based path ensures the player sees this even if
      # prevPs is unavailable (e.g. fresh client connection on
      # the same turn the ETAC lands).
      let sysName =
        if evt.systemId.isSome:
          sysLabel(ps.visibleSystems, evt.systemId.get())
        else: "Unknown System"
      var lines: seq[string] = @[
        "System: " & sysName,
      ]
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Operations,
        title: "Colony Established — " & sysName,
        summary: "A new colony has been founded at " &
          sysName & ".",
        detail: lines,
        isUnread: true,
        linkView: 2, linkLabel: "Planets",
      ))

    of GameEventType.CommandRejected,
        GameEventType.CommandFailed,
        GameEventType.CommandAborted:
      let statusStr =
        case evt.eventType
        of GameEventType.CommandRejected: "Rejected"
        of GameEventType.CommandFailed:   "Failed"
        of GameEventType.CommandAborted:  "Aborted"
        else: "Issue"
      var lines: seq[string] = @[]
      if evt.orderType.isSome:
        lines.add("Order: " & evt.orderType.get())
      if evt.reason.isSome:
        lines.add("Reason: " & evt.reason.get())
      if evt.fleetId.isSome:
        lines.add("Fleet: " & $evt.fleetId.get())
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Operations,
        title: "Command " & statusStr,
        summary: evt.description,
        detail: lines,
        isUnread: true,
        linkView: 4, linkLabel: "Fleets",
      ))
    else:
      discard

proc generateIntelPayloadReports(
    events: seq[GameEvent],
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate reports from intelligence payload events.
  result = @[]
  let us = ps.viewingHouse
  for evt in events:
    case evt.eventType
    of GameEventType.IntelGathered:
      # Show only to the gathering house
      if evt.houseId == some(us):
        let sysName =
          if evt.systemId.isSome:
            sysLabel(ps.visibleSystems,
              evt.systemId.get())
          else: "Unknown System"
        var lines: seq[string] = @[]
        if evt.details.isSome:
          for line in evt.details.get().split(", "):
            lines.add(line)
        if lines.len == 0 and evt.description.len > 0:
          lines.add(evt.description)
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Intelligence Report — " & sysName,
          summary: evt.description,
          detail: lines,
          isUnread: true,
          linkView: 2, linkLabel: "View System",
        ))
    of GameEventType.ScoutDetected:
      let sysName =
        if evt.systemId.isSome:
          sysLabel(ps.visibleSystems,
            evt.systemId.get())
        else: "Unknown System"
      # Dual perspective: scout owner vs detector
      if evt.targetHouseId == some(us):
        # We are the scout owner (targetHouseId = owner
        # whose scout was detected)
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Scout Operation Compromised — " &
            sysName,
          summary: "Your scout was detected at " &
            sysName & ".",
          detail: @[
            "System: " & sysName,
            evt.description,
          ],
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))
      elif evt.sourceHouseId == some(us):
        # We are the detector
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Enemy Spies Discovered — " & sysName,
          summary: "Enemy scouts detected in " &
            sysName & ".",
          detail: @[
            "System: " & sysName,
            evt.description,
          ],
          isUnread: true,
          linkView: 8, linkLabel: "Intel",
        ))
    of GameEventType.ScoutDestroyed:
      # Show only to the scout owner
      if evt.houseId == some(us):
        let sysName =
          if evt.systemId.isSome:
            sysLabel(ps.visibleSystems,
              evt.systemId.get())
          else: "Unknown System"
        result.add(ReportEntry(
          id: nextId(),
          turn: int(ps.turn),
          category: ReportCategory.Intelligence,
          title: "Scout Fleet Lost — " & sysName,
          summary: "Your scout fleet was destroyed " &
            "at " & sysName & ".",
          detail: @[
            "System: " & sysName,
            evt.description,
          ],
          isUnread: true,
          linkView: 3, linkLabel: "Fleets",
        ))
    else:
      discard

# =============================================================================
# Diplomacy Event Reports
# =============================================================================

proc generateDiplomacyEventReports(
    events: seq[GameEvent],
    ps: ps_types.PlayerState
): seq[ReportEntry] =
  ## Generate reports from diplomatic events (treaty lifecycle
  ## and relation changes). These carry structured narrative
  ## not reliably inferable from pendingProposals diffs alone.
  result = @[]
  let us = ps.viewingHouse

  for evt in events:
    case evt.eventType

    of GameEventType.TreatyProposed:
      # Only report if we are the proposer or the target
      let isProposer = evt.sourceHouseId == some(us)
      let isTarget   = evt.targetHouseId == some(us)
      if not isProposer and not isTarget:
        continue
      let otherHouseId =
        if isProposer: evt.targetHouseId
        else: evt.sourceHouseId
      let otherName =
        if otherHouseId.isSome:
          ps.houseNames.getOrDefault(
            otherHouseId.get(), "Unknown House")
        else: "Unknown House"
      let proposalDesc =
        evt.proposalType.get("De-escalation")
      let (title, summary) =
        if isProposer:
          ("Treaty Proposed — " & otherName,
           "Your " & proposalDesc &
             " proposal has been sent to House " &
             otherName & ".")
        else:
          ("Treaty Offer Received — " & otherName,
           "House " & otherName &
             " has proposed a " & proposalDesc &
             ". Respond via the Diplomacy panel.")
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: title,
        summary: summary,
        detail: @[
          summary,
          "Proposal type: " & proposalDesc,
          "Expires if not answered.",
        ],
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    of GameEventType.TreatyAccepted:
      let otherHouseId =
        if evt.sourceHouseId == some(us):
          evt.targetHouseId
        else: evt.sourceHouseId
      let otherName =
        if otherHouseId.isSome:
          ps.houseNames.getOrDefault(
            otherHouseId.get(), "Unknown House")
        else: "Unknown House"
      let proposalDesc =
        evt.proposalType.get("De-escalation")
      var lines = @[
        "House " & otherName &
          " accepted the " & proposalDesc &
          " proposal.",
      ]
      if evt.newState.isSome:
        lines.add("New relation: " & $evt.newState.get())
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: "Treaty Accepted — " & otherName,
        summary: "The " & proposalDesc &
          " with House " & otherName &
          " has been accepted.",
        detail: lines,
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    of GameEventType.TreatyBroken:
      let otherHouseId =
        if evt.sourceHouseId == some(us):
          evt.targetHouseId
        else: evt.sourceHouseId
      let otherName =
        if otherHouseId.isSome:
          ps.houseNames.getOrDefault(
            otherHouseId.get(), "Unknown House")
        else: "Unknown House"
      let reason =
        evt.changeReason.get("Expired or violated")
      var lines = @[reason]
      if evt.newState.isSome:
        lines.add("New relation: " & $evt.newState.get())
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: "Treaty Broken — " & otherName,
        summary: "Agreement with House " & otherName &
          " has ended: " & reason,
        detail: lines,
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    of GameEventType.WarDeclared:
      # Public event — visible to all houses
      let attackerName =
        if evt.sourceHouseId.isSome:
          ps.houseNames.getOrDefault(
            evt.sourceHouseId.get(), "Unknown House")
        else: "Unknown House"
      let defenderName =
        if evt.targetHouseId.isSome:
          ps.houseNames.getOrDefault(
            evt.targetHouseId.get(), "Unknown House")
        else: "Unknown House"
      let isUs =
        evt.sourceHouseId == some(us) or
        evt.targetHouseId == some(us)
      let summary =
        if isUs:
          if evt.sourceHouseId == some(us):
            "You have declared war on House " &
              defenderName & "."
          else:
            "House " & attackerName &
              " has declared war on you!"
        else:
          "House " & attackerName &
            " has declared war on House " &
            defenderName & "."
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: "War Declared — " & attackerName &
          " vs " & defenderName,
        summary: summary,
        detail: @[summary, evt.description],
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    of GameEventType.PeaceSigned:
      # Public event — visible to all houses
      let houseAName =
        if evt.sourceHouseId.isSome:
          ps.houseNames.getOrDefault(
            evt.sourceHouseId.get(), "Unknown House")
        else: "Unknown House"
      let houseBName =
        if evt.targetHouseId.isSome:
          ps.houseNames.getOrDefault(
            evt.targetHouseId.get(), "Unknown House")
        else: "Unknown House"
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: "Peace Signed — " & houseAName &
          " & " & houseBName,
        summary: "Houses " & houseAName & " and " &
          houseBName & " have ceased hostilities.",
        detail: @[evt.description],
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    of GameEventType.DiplomaticRelationChanged:
      # Only report if we are directly involved; the
      # diff-based generator already covers this for all
      # houses so we restrict to avoid double-reporting
      # for third-party observers.
      let weAreInvolved =
        evt.sourceHouseId == some(us) or
        evt.targetHouseId == some(us)
      if not weAreInvolved:
        continue
      let otherHouseId =
        if evt.sourceHouseId == some(us):
          evt.targetHouseId
        else: evt.sourceHouseId
      let otherName =
        if otherHouseId.isSome:
          ps.houseNames.getOrDefault(
            otherHouseId.get(), "Unknown House")
        else: "Unknown House"
      let reason =
        evt.changeReason.get("")
      var lines: seq[string] = @[]
      if evt.oldState.isSome and evt.newState.isSome:
        lines.add($evt.oldState.get() & " → " &
          $evt.newState.get())
      if reason.len > 0:
        lines.add("Reason: " & reason)
      if evt.description.len > 0:
        lines.add(evt.description)
      result.add(ReportEntry(
        id: nextId(),
        turn: int(ps.turn),
        category: ReportCategory.Diplomacy,
        title: "Diplomatic Change — " & otherName,
        summary: evt.description,
        detail: lines,
        isUnread: true,
        linkView: 7, linkLabel: "Diplomacy",
      ))

    else:
      discard

# =============================================================================
# Public API
# =============================================================================

proc generateClientReports*(
    ps: ps_types.PlayerState,
    prevPs: Option[ps_types.PlayerState] =
      none(ps_types.PlayerState)
): seq[ReportEntry] =
  ## Generate the full client-side report list from PlayerState.
  ##
  ## On turn 1 emits a welcome/intro report with House lore and
  ## game hints. On subsequent turns, if prevPs is provided,
  ## generates diff-based narrative reports comparing the two
  ## snapshots.
  ##
  ## prevPs should be the previous turn's cached PlayerState,
  ## loaded by the caller from TuiCache.loadPlayerState before
  ## calling syncPlayerStateToModel.
  nextReportId = 100
  result = @[]

  if ps.turn <= 1:
    let hname =
      ps.houseNames.getOrDefault(
        ps.viewingHouse, "Unknown")
    result.add(generateIntroReport(hname, ps.turn))

  if prevPs.isSome:
    let prev = prevPs.get()
    result.add(generateColonyReports(prev, ps))
    result.add(generateFleetReports(prev, ps))
    result.add(generateShipReports(prev, ps))
    result.add(generateIntelReports(prev, ps))
    result.add(generateStalenessAlerts(prev, ps))
    result.add(generateDiplomacyReports(prev, ps))
    result.add(generateEconomyReports(prev, ps))
    result.add(generateTurnSummary(prev, ps))

  # Event-based reports (Phase 2)
  # These report on things that cannot be inferred from
  # PlayerState diffs alone: combat details, espionage
  # outcomes, command rejections, etc.
  if ps.turnEvents.len > 0:
    result.add(generateCombatReports(ps.turnEvents, ps))
    result.add(generateEspionageReports(ps.turnEvents, ps))
    result.add(generateCommandReports(ps.turnEvents, ps))
    result.add(generateIntelPayloadReports(ps.turnEvents, ps))
    result.add(
      generateDiplomacyEventReports(ps.turnEvents, ps))
