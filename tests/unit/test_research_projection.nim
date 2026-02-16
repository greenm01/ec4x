## Unit tests for projected research gating helpers.

import std/[unittest, tables]

import ../../src/engine/systems/tech/costs
import ../../src/engine/types/tech
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine
import ../../src/player/sam/tui_model
import ../../src/player/tui/data/research_projection
import ../../src/player/tui/data/tech_info

gameConfig = config_engine.loadGameConfig()

proc baseLevels(sl: int32 = 1, el: int32 = 1, wep: int32 = 1): TechLevel =
  TechLevel(
    el: el,
    sl: sl,
    cst: 1,
    wep: wep,
    ter: 1,
    eli: 1,
    clk: 1,
    sld: 1,
    cic: 1,
    stl: 1,
    fc: 1,
    sc: 1,
    fd: 1,
    aco: 1
  )

proc emptyPoints(): ResearchPoints =
  ResearchPoints(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int32]()
  )

proc emptyAllocation(): ResearchAllocation =
  ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int32]()
  )

suite "Research Projection: Science Level":
  test "science allocation can project one SL level":
    let levels = baseLevels(sl = 1)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    alloc.science = slUpgradeCost(1)

    check projectedScienceLevel(levels, points, alloc) == 2

  test "projection never advances without threshold":
    let levels = baseLevels(sl = 1)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    alloc.science = slUpgradeCost(1) - 1

    check projectedScienceLevel(levels, points, alloc) == 1

suite "Research Projection: Gating":
  test "EL remains blocked without projected SL":
    let levels = baseLevels(sl = 1, el = 1)
    let points = emptyPoints()
    let alloc = emptyAllocation()
    let item = researchItemAt(researchIndexForCode("EL"))

    check maxProjectedAllocation(levels, points, alloc, item) == 0
    check isBlockedProjected(levels, points, alloc, item)

  test "EL unlocks when SL projects to required tier":
    let levels = baseLevels(sl = 1, el = 1)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    alloc.science = slUpgradeCost(1)
    let item = researchItemAt(researchIndexForCode("EL"))

    check maxProjectedAllocation(levels, points, alloc, item) ==
      elUpgradeCost(1).int

suite "Research Projection: Tech Level":
  test "projected tech level stays at current without threshold":
    let levels = baseLevels(sl = 1, wep = 1)
    let points = emptyPoints()
    let alloc = emptyAllocation()
    let item = researchItemAt(researchIndexForCode("WEP"))

    check projectedTechLevel(levels, points, alloc, item) == 1

  test "projected tech level advances when staged PP meets threshold":
    let levels = baseLevels(sl = 1, wep = 1)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    let item = researchItemAt(researchIndexForCode("WEP"))
    alloc.technology[item.field] = techProgressCost(item, 1).int32

    check projectedTechLevel(levels, points, alloc, item) == 2

  test "projected tech level uses existing progress plus staged PP":
    let levels = baseLevels(sl = 1, wep = 1)
    var points = emptyPoints()
    var alloc = emptyAllocation()
    let item = researchItemAt(researchIndexForCode("WEP"))
    let cost = techProgressCost(item, 1)
    points.technology[item.field] = (cost - 1).int32
    alloc.technology[item.field] = 1

    check projectedTechLevel(levels, points, alloc, item) == 2

  test "projected tech level is capped at max level":
    let item = researchItemAt(researchIndexForCode("WEP"))
    let maxLevel = progressionMaxLevel(item)
    let levels = baseLevels(sl = 1, wep = maxLevel.int32)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    alloc.technology[item.field] = 999

    check projectedTechLevel(levels, points, alloc, item) == maxLevel

  test "projected tech level remains capped at one level per turn":
    let levels = baseLevels(sl = 1, wep = 1)
    let points = emptyPoints()
    var alloc = emptyAllocation()
    let item = researchItemAt(researchIndexForCode("WEP"))
    alloc.technology[item.field] = 999

    check projectedTechLevel(levels, points, alloc, item) == 2
