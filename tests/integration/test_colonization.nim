## Integration test for colonization system

import std/[unittest, options, strutils]
import ../../src/engine/colonization/engine
import ../../src/engine/economy/types as econ_types
import ../../src/engine/prestige
import ../../src/engine/config/prestige_config
import ../../src/common/types/[core, planets]

suite "Colonization System":

  test "Can colonize empty system":
    let systemId = 42.SystemId
    let existingColonies: seq[econ_types.Colony] = @[]

    check canColonize(systemId, existingColonies) == true

  test "Cannot colonize occupied system":
    let systemId = 42.SystemId
    let existingColonies = @[
      econ_types.initColony(systemId, "house1".HouseId, PlanetClass.Benign, ResourceRating.Abundant, 10)
    ]

    check canColonize(systemId, existingColonies) == false

  test "Establish colony creates colony and awards prestige":
    let houseId = "house1".HouseId
    let systemId = 100.SystemId

    let result = establishColony(
      houseId,
      systemId,
      PlanetClass.Lush,
      ResourceRating.Rich,
      startingPTU = 5
    )

    check result.success == true
    check result.newColony.isSome

    let colony = result.newColony.get()
    check colony.owner == houseId
    check colony.systemId == systemId
    check colony.populationUnits == 5
    check colony.planetClass == PlanetClass.Lush

    # Check prestige event
    check result.prestigeEvent.isSome
    let prestigeEvent = result.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.ColonyEstablished
    check prestigeEvent.amount == globalPrestigeConfig.establishColony  # +5

  test "Colonization attempt succeeds on empty system":
    let attempt = ColonizationAttempt(
      houseId: "house1".HouseId,
      systemId: 200.SystemId,
      fleetId: "fleet1".FleetId,
      ptuUsed: 3
    )

    let result = attemptColonization(
      attempt,
      existingColonies = @[],
      PlanetClass.Benign,
      ResourceRating.Abundant
    )

    check result.success == true
    check result.newColony.isSome
    check result.prestigeEvent.isSome

  test "Colonization attempt fails on occupied system":
    let systemId = 300.SystemId
    let existingColonies = @[
      econ_types.initColony(systemId, "house2".HouseId, PlanetClass.Benign, ResourceRating.Abundant, 10)
    ]

    let attempt = ColonizationAttempt(
      houseId: "house1".HouseId,
      systemId: systemId,
      fleetId: "fleet1".FleetId,
      ptuUsed: 3
    )

    let result = attemptColonization(
      attempt,
      existingColonies,
      PlanetClass.Benign,
      ResourceRating.Abundant
    )

    check result.success == false
    check result.reason.contains("already colonized")
    check result.newColony.isNone
    check result.prestigeEvent.isNone

  test "Colonization attempt fails without PTU":
    let attempt = ColonizationAttempt(
      houseId: "house1".HouseId,
      systemId: 400.SystemId,
      fleetId: "fleet1".FleetId,
      ptuUsed: 0  # No PTU
    )

    let result = attemptColonization(
      attempt,
      existingColonies = @[],
      PlanetClass.Benign,
      ResourceRating.Abundant
    )

    check result.success == false
    check result.reason.contains("Insufficient PTU")
    check result.newColony.isNone
