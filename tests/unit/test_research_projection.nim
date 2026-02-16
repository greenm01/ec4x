## Unit tests for projected research gating helpers.

import std/[unittest, tables]

import ../../src/engine/systems/tech/costs
import ../../src/engine/types/tech
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine
import ../../src/player/sam/tui_model
import ../../src/player/tui/data/research_projection

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
