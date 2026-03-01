## dump_state - Dump game state for a house (LLM-optimized output)
##
## Loads the game state from a per-game SQLite database, applies fog-of-war
## filtering for a specific house, then outputs a compact structured summary
## optimized for LLM analysis and debugging.
##
## Usage:
##   nim r tools/dump_state.nim <game-slug> --house N
##
## Options:
##   --house N    House ID to view state for (1-based, required)
##
## Output goes to stdout. Redirect to a file if needed:
##   nim r tools/dump_state.nim my-game --house 1 > state.txt

import std/[os, strutils, tables, options, strformat, sequtils, algorithm]
import ../src/daemon/persistence/reader
import ../src/engine/state/player_state
import ../src/engine/types/[
  core, player_state, colony, fleet, ship, tech, diplomacy,
  ground_unit, facilities, progression, event, combat]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc opt(x: Option[int32]): string =
  if x.isSome: $x.get else: "?"

proc opt(x: Option[int]): string =
  if x.isSome: $x.get else: "?"

proc optStr(x: Option[string]): string =
  if x.isSome: x.get else: "?"

proc optBool(x: Option[bool]): string =
  if x.isSome: (if x.get: "yes" else: "no") else: "?"

proc optHouse(x: Option[HouseId]): string =
  if x.isSome: "H" & $uint32(x.get) else: "?"

proc optFleet(x: Option[FleetId]): string =
  if x.isSome: "F" & $uint32(x.get) else: "?"

proc sysName(ps: PlayerState, sysId: SystemId): string =
  if sysId in ps.visibleSystems:
    ps.visibleSystems[sysId].name
  else:
    "S" & $uint32(sysId)

proc houseName(ps: PlayerState, hId: HouseId): string =
  if hId in ps.houseNames:
    ps.houseNames[hId]
  else:
    "H" & $uint32(hId)

# ---------------------------------------------------------------------------
# Section renderers
# ---------------------------------------------------------------------------

proc renderHeader(ps: PlayerState, gameSlug: string): string =
  result = &"# EC4X State Dump: {gameSlug}\n"
  result &= &"Turn: {ps.turn}  House: {uint32(ps.viewingHouse)}"
  if ps.viewingHouse in ps.houseNames:
    result &= &" ({ps.houseNames[ps.viewingHouse]})"
  result &= "\n"

proc renderEconomy(ps: PlayerState): string =
  result = "\n## Economy\n"
  result &= &"Treasury: {opt(ps.treasuryBalance)} PP\n"
  result &= &"Net Income: {opt(ps.netIncome)} PP/turn\n"
  result &= &"Tax Rate: {opt(ps.taxRate)}%\n"
  result &= &"EBP Pool: {opt(ps.ebpPool)}\n"
  result &= &"CIP Pool: {opt(ps.cipPool)}\n"

proc renderTech(ps: PlayerState): string =
  result = "\n## Technology\n"
  if ps.techLevels.isNone:
    return result & "(no data)\n"
  let t = ps.techLevels.get
  result &= &"EL:{t.el} SL:{t.sl} | " &
    &"CST:{t.cst} WEP:{t.wep} TER:{t.ter} ELI:{t.eli} " &
    &"CLK:{t.clk} SLD:{t.sld} CIC:{t.cic} STL:{t.stl} " &
    &"FC:{t.fc} SC:{t.sc} FD:{t.fd} ACO:{t.aco}\n"
  if ps.researchPoints.isSome:
    let rp = ps.researchPoints.get
    result &= &"Research: ERP:{rp.economic} SRP:{rp.science}"
    var techEntries: seq[string]
    for field, pts in rp.technology.pairs:
      if pts > 0:
        techEntries.add($field & ":" & $pts)
    if techEntries.len > 0:
      result &= " TRP:[" & techEntries.join(" ") & "]"
    result &= "\n"

proc renderColonies(ps: PlayerState): string =
  result = "\n## Colonies (" & $ps.ownColonies.len & ")\n"
  for c in ps.ownColonies:
    let sysStr = ps.sysName(c.systemId)
    result &= &"  Colony {uint32(c.id)} @ {sysStr}"
    if c.blockaded:
      result &= " [BLOCKADED"
      if c.blockadedBy.len > 0:
        result &= " by " & c.blockadedBy.mapIt("H" & $uint32(it)).join(",")
      result &= "]"
    result &= "\n"
    result &= &"    Pop:{c.populationUnits}PU  Infra:{c.infrastructure}IU" &
      &"  Industry:{c.industrial.units}IU\n"
    result &= &"    Output:{c.grossOutput} NCV:{c.netValue}" &
      &"  Tax:{c.taxRate}%\n"

    # Facilities
    let neoCount = c.neoriaIds.len
    let kaCount = c.kastraIds.len
    if neoCount > 0 or kaCount > 0:
      result &= &"    Facilities: {neoCount} neoria  {kaCount} kastra"
      result &= &"  CD:{c.constructionDocks} RD:{c.repairDocks}\n"

    # Construction queue
    if c.underConstruction.isSome:
      result &= &"    Building: project {uint32(c.underConstruction.get)}"
      if c.constructionQueue.len > 1:
        result &= &" (+{c.constructionQueue.len - 1} queued)"
      result &= "\n"
    elif c.constructionQueue.len > 0:
      result &= &"    Queue: {c.constructionQueue.len} projects\n"

    # Ground units on this colony
    let guIds = c.groundUnitIds
    if guIds.len > 0:
      result &= &"    Ground units: {guIds.len} (see Ground Forces section)\n"

    # Terraforming
    if c.activeTerraforming.isSome:
      let tf = c.activeTerraforming.get
      result &= &"    Terraforming: {tf.turnsRemaining} turns left" &
        &" -> class {tf.targetClass}\n"

    # Auto flags
    var flags: seq[string]
    if c.autoRepair: flags.add("auto-repair")
    if c.autoLoadMarines: flags.add("auto-marines")
    if c.autoLoadFighters: flags.add("auto-fighters")
    if flags.len > 0:
      result &= "    Auto: " & flags.join(", ") & "\n"

proc renderFleets(ps: PlayerState): string =
  result = "\n## Fleets (" & $ps.ownFleets.len & ")\n"

  # Build ship lookup by fleet
  var shipsByFleet = initTable[FleetId, seq[Ship]]()
  for s in ps.ownShips:
    if s.fleetId notin shipsByFleet:
      shipsByFleet[s.fleetId] = @[]
    shipsByFleet[s.fleetId].add(s)

  for f in ps.ownFleets:
    let sysStr = ps.sysName(f.location)
    result &= &"  Fleet {f.name} (F{uint32(f.id)}) @ {sysStr}" &
      &" [{f.status}] ROE:{f.roe}\n"
    result &= &"    Cmd: {f.command.commandType}"
    if f.command.targetSystem.isSome:
      result &= &" -> {ps.sysName(f.command.targetSystem.get)}"
    if f.command.targetFleet.isSome:
      result &= &" fleet F{uint32(f.command.targetFleet.get)}"
    result &= &"  Mission: {f.missionState}\n"

    let ships = shipsByFleet.getOrDefault(f.id, @[])
    if ships.len > 0:
      # Group by class
      var classCounts = initTable[ShipClass, int]()
      var classCrippled = initTable[ShipClass, int]()
      for s in ships:
        classCounts[s.shipClass] = classCounts.getOrDefault(s.shipClass, 0) + 1
        if s.state == CombatState.Crippled:
          classCrippled[s.shipClass] =
            classCrippled.getOrDefault(s.shipClass, 0) + 1
      var parts: seq[string]
      for cls, cnt in classCounts.pairs:
        var p = $cnt & "x" & $cls
        let crip = classCrippled.getOrDefault(cls, 0)
        if crip > 0: p &= "(" & $crip & "crip)"
        parts.add(p)
      result &= "    Ships: " & parts.join("  ") & "\n"
      # Per-ship detail: ID and class (useful for ZTC orders)
      for s in ships:
        var detail = &"      (ShipId){uint32(s.id)} [{s.shipClass}] fleetId={uint32(s.fleetId)}"
        if s.state == CombatState.Crippled: detail &= " CRIPPLED"
        if s.embarkedFighters.len > 0:
          let fIds = s.embarkedFighters.mapIt(
            "(ShipId)" & $uint32(it)).join(" ")
          detail &= &" fighters=[{fIds}]"
        if s.assignedToCarrier.isSome:
          detail &= &" carrier=(ShipId)" &
            $uint32(s.assignedToCarrier.get)
        result &= detail & "\n"
    else:
      result &= "    Ships: (empty)\n"

proc renderGroundForces(ps: PlayerState): string =
  if ps.ownGroundUnits.len == 0:
    return ""
  result = "\n## Ground Forces (" & $ps.ownGroundUnits.len & ")\n"

  # Group by colony
  var byColony = initTable[ColonyId, seq[GroundUnit]]()
  var onTransport: seq[GroundUnit]
  for u in ps.ownGroundUnits:
    case u.garrison.locationType
    of GroundUnitLocation.OnColony:
      let cid = u.garrison.colonyId
      if cid notin byColony: byColony[cid] = @[]
      byColony[cid].add(u)
    of GroundUnitLocation.OnTransport:
      onTransport.add(u)

  for cid, units in byColony.pairs:
    var counts = initTable[GroundClass, int]()
    for u in units:
      counts[u.stats.unitType] =
        counts.getOrDefault(u.stats.unitType, 0) + 1
    var parts: seq[string]
    for cls, cnt in counts.pairs:
      parts.add($cnt & "x" & $cls)
    result &= &"  Colony {uint32(cid)}: " & parts.join("  ") & "\n"

  if onTransport.len > 0:
    var counts = initTable[GroundClass, int]()
    for u in onTransport:
      counts[u.stats.unitType] =
        counts.getOrDefault(u.stats.unitType, 0) + 1
    var parts: seq[string]
    for cls, cnt in counts.pairs:
      parts.add($cnt & "x" & $cls)
    result &= "  On transports: " & parts.join("  ") & "\n"

proc renderOrbitalAssets(ps: PlayerState): string =
  if ps.ownNeorias.len == 0 and ps.ownKastras.len == 0:
    return ""
  result = "\n## Orbital Assets\n"
  if ps.ownNeorias.len > 0:
    result &= &"  Neorias ({ps.ownNeorias.len}):\n"
    for n in ps.ownNeorias:
      result &= &"    N{uint32(n.id)} [{n.neoriaClass}]" &
        &" colony {uint32(n.colonyId)}" &
        &" CD:{n.effectiveDocks} [{n.state}]\n"
  if ps.ownKastras.len > 0:
    result &= &"  Kastras / Starbases ({ps.ownKastras.len}):\n"
    for k in ps.ownKastras:
      result &= &"    K{uint32(k.id)} [{k.kastraClass}]" &
        &" colony {uint32(k.colonyId)}" &
        &" AS:{k.stats.attackStrength} DS:{k.stats.defenseStrength}" &
        &" WEP:{k.stats.wep} [{k.state}]\n"

proc renderIntelligence(ps: PlayerState): string =
  result = "\n## Intelligence\n"
  result &= &"Visible systems: {ps.visibleSystems.len}  " &
    &"Enemy colonies: {ps.visibleColonies.len}  " &
    &"Enemy fleets: {ps.visibleFleets.len}\n"

  if ps.visibleColonies.len > 0:
    result &= "Enemy colonies:\n"
    for vc in ps.visibleColonies:
      let sysStr = ps.sysName(vc.systemId)
      let owner = ps.houseName(vc.owner)
      result &= &"  Colony {uint32(vc.colonyId)} @ {sysStr} ({owner})"
      if vc.intelTurn.isSome:
        result &= &" [intel T{vc.intelTurn.get}]"
      result &= "\n"
      if vc.estimatedPopulation.isSome or vc.estimatedIndustry.isSome:
        result &= &"    Est: Pop~{opt(vc.estimatedPopulation)}" &
          &" Ind~{opt(vc.estimatedIndustry)}"
        if vc.estimatedArmies.isSome:
          result &= &" Armies~{opt(vc.estimatedArmies)}"
        if vc.estimatedMarines.isSome:
          result &= &" Marines~{opt(vc.estimatedMarines)}"
        result &= "\n"

  if ps.visibleFleets.len > 0:
    result &= "Enemy fleets:\n"
    for vf in ps.visibleFleets:
      let sysStr = ps.sysName(vf.location)
      let owner = ps.houseName(vf.owner)
      result &= &"  Fleet F{uint32(vf.fleetId)} ({owner}) @ {sysStr}"
      if vf.intelTurn.isSome:
        result &= &" [T{vf.intelTurn.get}]"
      if vf.estimatedShipCount.isSome:
        result &= &" ~{opt(vf.estimatedShipCount)} ships"
      result &= "\n"

proc renderStarmap(ps: PlayerState): string =
  result = "\n## Starmap (visible systems)\n"
  result &= "Format: S<id> <name> [<visibility>] lanes-><id,...>\n"
  var sysList: seq[VisibleSystem]
  for _, vs in ps.visibleSystems.pairs:
    sysList.add(vs)
  sysList.sort(proc(a, b: VisibleSystem): int =
    cmp(uint32(a.systemId), uint32(b.systemId)))
  for vs in sysList:
    let laneIds = vs.jumpLaneIds.mapIt($uint32(it)).join(",")
    result &= &"  S{uint32(vs.systemId)} {vs.name}" &
      &" [{vs.visibility}] lanes->{laneIds}\n"

proc renderDiplomacy(ps: PlayerState): string =
  if ps.diplomaticRelations.len == 0 and
      ps.pendingProposals.len == 0 and
      ps.eliminatedHouses.len == 0:
    return ""
  result = "\n## Diplomacy\n"
  if ps.diplomaticRelations.len > 0:
    result &= "Relations:\n"
    for pair, rel in ps.diplomaticRelations.pairs:
      let aName = ps.houseName(pair[0])
      let bName = ps.houseName(pair[1])
      result &= &"  {aName} -> {bName}: {rel}\n"
  if ps.pendingProposals.len > 0:
    result &= "Pending proposals:\n"
    for p in ps.pendingProposals:
      let fromHouse = ps.houseName(p.proposer)
      let toHouse = ps.houseName(p.target)
      result &= &"  [{p.status}] P{uint32(p.id)} {fromHouse} -> {toHouse}:" &
        &" {p.proposalType} (expires T{p.expiresOnTurn})\n"
  if ps.eliminatedHouses.len > 0:
    let names = ps.eliminatedHouses.mapIt(ps.houseName(it))
    result &= "Eliminated: " & names.join(", ") & "\n"

proc renderStandings(ps: PlayerState): string =
  result = "\n## Public Standings\n"
  # Collect and sort by prestige descending
  var entries: seq[tuple[
    hId: HouseId, prestige: int32, colonies: int32, name: string]]
  for hId, pres in ps.housePrestige.pairs:
    let cols = ps.houseColonyCounts.getOrDefault(hId, 0)
    entries.add((hId, pres, cols, ps.houseName(hId)))
  entries.sort(
    proc(
      a, b: tuple[hId: HouseId, prestige: int32,
        colonies: int32, name: string]
    ): int =
      cmp(b.prestige, a.prestige)
  )
  for e in entries:
    let marker = if e.hId == ps.viewingHouse: " <-- YOU" else: ""
    result &= &"  {e.name}: {e.prestige} prestige  {e.colonies} colonies{marker}\n"

proc renderActProgression(ps: PlayerState): string =
  let ap = ps.actProgression
  result = "\n## Act Progression\n"
  result &= &"Act: {ap.currentAct}  (started T{ap.actStartTurn})\n"
  if ap.act2TopThreeHouses.len > 0:
    let names = ap.act2TopThreeHouses.mapIt(ps.houseName(it))
    result &= "Act2 top-3: " & names.join(", ") & "\n"

proc renderEvent(ev: GameEvent, ps: PlayerState): string =
  ## Compact single-line event summary (kind + key fields)
  result = &"[T{ev.turn}]"
  if ev.houseId.isSome:
    result &= " H" & $uint32(ev.houseId.get)
  result &= " " & $ev.eventType

  # Type-specific key fields
  case ev.eventType
  of CommandIssued, CommandCompleted, CommandRejected, CommandFailed,
      CommandAborted, FleetArrived:
    if ev.orderType.isSome: result &= " " & optStr(ev.orderType)
    if ev.reason.isSome: result &= " reason=" & optStr(ev.reason)
    if ev.fleetId.isSome: result &= " fleet=" & optFleet(ev.fleetId)
  of CombatResult, SystemCaptured, ColonyCaptured, InvasionRepelled:
    if ev.systemId.isSome: result &= " @" & ps.sysName(ev.systemId.get)
    if ev.outcome.isSome: result &= " " & optStr(ev.outcome)
    if ev.attackerLosses.isSome:
      result &= &" atk-loss={opt(ev.attackerLosses)}" &
        &" def-loss={opt(ev.defenderLosses)}"
    if ev.newOwner.isSome: result &= " new-owner=" & optHouse(ev.newOwner)
  of GameEventType.Research, GameEventType.TechAdvance:
    result &= &" {ev.techField}"
    if ev.oldLevel.isSome:
      result &= &" {opt(ev.oldLevel)}->{opt(ev.newLevel)}"
    if ev.breakthrough.isSome:
      result &= " breakthrough=" & optStr(ev.breakthrough)
  of GameEventType.Diplomacy, WarDeclared, PeaceSigned,
      DiplomaticRelationChanged,
      TreatyProposed, TreatyAccepted, TreatyBroken:
    if ev.sourceHouseId.isSome:
      result &= " " & optHouse(ev.sourceHouseId) &
        "->" & optHouse(ev.targetHouseId)
    if ev.oldState.isSome:
      result &= &" {ev.oldState.get}->{ev.newState.get}"
    if ev.changeReason.isSome:
      result &= " (" & optStr(ev.changeReason) & ")"
  of GameEventType.Economy, ConstructionStarted, SalvageRecovered,
      PopulationTransfer, PopulationTransferCompleted,
      PopulationTransferLost, InfrastructureDamage:
    if ev.category.isSome: result &= " " & optStr(ev.category)
    if ev.amount.isSome: result &= &" amount={opt(ev.amount)}"
  of GameEventType.Colony, ColonyEstablished, BuildingCompleted,
      UnitRecruited,
      UnitDisbanded, TerraformComplete, RepairQueued, RepairCancelled,
      EntitySalvaged, ConstructionLost:
    if ev.systemId.isSome: result &= " @" & ps.sysName(ev.systemId.get)
    if ev.colonyEventType.isSome:
      result &= " " & optStr(ev.colonyEventType)
    if ev.salvageValueColony.isSome:
      result &= &" refund={opt(ev.salvageValueColony)}PP"
  of GameEventType.Fleet, FleetDestroyed, ShipCommissioned, ScoutDestroyed,
      FleetDisbanded,
      SquadronDisbanded, SquadronScrapped, RepairStalled, RepairCompleted:
    if ev.fleetId.isSome: result &= " " & optFleet(ev.fleetId)
    if ev.fleetEventType.isSome: result &= " " & optStr(ev.fleetEventType)
    if ev.shipClass.isSome: result &= " class=" & $ev.shipClass.get
    if ev.salvageValue.isSome:
      result &= &" salvage={opt(ev.salvageValue)}PP"
  of GameEventType.Prestige, PrestigeGained, PrestigeLost:
    result &= &" delta={opt(ev.changeAmount)}"
    if ev.details.isSome: result &= " " & optStr(ev.details)
  of HouseEliminated:
    if ev.houseId.isSome: result &= " " & ps.houseName(ev.houseId.get)
    if ev.eliminatedBy.isSome:
      result &= " by=" & ps.houseName(ev.eliminatedBy.get)
  of GameEventType.Espionage, SpyMissionSucceeded, SabotageConducted,
      TechTheftExecuted,
      AssassinationAttempted, EconomicManipulationExecuted,
      CyberAttackConducted, PsyopsCampaignLaunched, IntelTheftExecuted,
      DisinformationPlanted, CounterIntelSweepExecuted, SpyMissionDetected:
    if ev.operationType.isSome: result &= " op=" & $ev.operationType.get
    result &= " success=" & optBool(ev.success)
    result &= " detected=" & optBool(ev.detected)
  of WeaponFired:
    if ev.attackerSquadronId.isSome:
      result &= " atk=" & optStr(ev.attackerSquadronId) &
        " -> tgt=" & optStr(ev.targetSquadronId)
    if ev.damageDealt.isSome: result &= &" dmg={opt(ev.damageDealt)}"
  of ShipDamaged:
    if ev.damagedSquadronId.isSome:
      result &= " sq=" & optStr(ev.damagedSquadronId)
    result &= &" dmg={opt(ev.damageAmount)} state=" & optStr(ev.shipNewState)
  of ShipDestroyed:
    if ev.destroyedSquadronId.isSome:
      result &= " sq=" & optStr(ev.destroyedSquadronId)
    if ev.killedBy.isSome: result &= " by=" & ps.houseName(ev.killedBy.get)
  of BombardmentRoundCompleted:
    result &= &" round={opt(ev.completedRound)}"
    if ev.infrastructureDestroyed.isSome:
      result &= &" IU-dest={opt(ev.infrastructureDestroyed)}"
    if ev.populationKilled.isSome:
      result &= &" PU-killed={opt(ev.populationKilled)}"
    if ev.facilitiesDestroyed.isSome and ev.facilitiesDestroyed.get > 0:
      result &= &" fac-dest={opt(ev.facilitiesDestroyed)}"
  of GroundCombatRound:
    if ev.attackerRoll.isSome:
      result &= &" atk-roll={opt(ev.attackerRoll)}" &
        &" def-roll={opt(ev.defenderRoll)}"
  of FleetRetreat:
    if ev.retreatingFleetId.isSome:
      result &= " fleet=" & optFleet(ev.retreatingFleetId)
    if ev.retreatReason.isSome:
      result &= " reason=" & optStr(ev.retreatReason)
  of GameEventType.Intelligence, IntelGathered, ScoutDetected:
    if ev.intelType.isSome: result &= " type=" & optStr(ev.intelType)
    if ev.systemId.isSome: result &= " @" & ps.sysName(ev.systemId.get)
  else:
    # Fall back to description for remaining event types
    if ev.description.len > 0 and ev.description.len <= 80:
      result &= " | " & ev.description

  result &= "\n"

proc renderEvents(ps: PlayerState): string =
  result = "\n## Turn Events (" & $ps.turnEvents.len & ")\n"
  if ps.turnEvents.len == 0:
    result &= "(none)\n"
    return
  for ev in ps.turnEvents:
    result &= "  " & renderEvent(ev, ps)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc usage() =
  echo "Usage: dump_state <game-slug> --house N"
  echo ""
  echo "  <game-slug>  Game identifier (matches data/games/<slug>/)"
  echo "  --house N    House ID to view state for (1-based)"
  quit(1)

proc main() =
  let args = commandLineParams()
  if args.len < 3:
    usage()

  let gameSlug = args[0]

  var houseId: int = -1
  var i = 1
  while i < args.len:
    if args[i] == "--house" and i + 1 < args.len:
      try:
        houseId = parseInt(args[i + 1])
      except ValueError:
        echo "Error: --house requires a numeric argument"
        usage()
      i += 2
    else:
      echo "Error: Unknown argument: " & args[i]
      usage()

  if houseId < 1:
    echo "Error: --house is required and must be >= 1"
    usage()

  let dbPath = "data/games" / gameSlug / "ec4x.db"
  if not fileExists(dbPath):
    echo "Error: Game database not found: " & dbPath
    echo "       Check that '" & gameSlug & "' is a valid game slug."
    quit(1)

  let state = loadFullState(dbPath)
  let ps = createPlayerState(state, HouseId(houseId.uint32))

  var output = renderHeader(ps, gameSlug)
  output &= renderEconomy(ps)
  output &= renderTech(ps)
  output &= renderColonies(ps)
  output &= renderFleets(ps)
  output &= renderGroundForces(ps)
  output &= renderOrbitalAssets(ps)
  output &= renderIntelligence(ps)
  output &= renderStarmap(ps)
  output &= renderDiplomacy(ps)
  output &= renderStandings(ps)
  output &= renderActProgression(ps)
  output &= renderEvents(ps)

  stdout.write(output)

when isMainModule:
  main()
