## Integration tests for the intelligence system
## Tests corruption, quality levels, staleness, and reporting

import std/[unittest, tables, options, random, math]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap, resolve]
import ../../src/engine/intelligence/[types, corruption, generator]
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/diplomacy/types as dip_types
import ../../src/engine/config/[espionage_config, diplomacy_config]
import ../../src/common/types/[core, units, combat]
import ../../src/common/[hex, system]

suite "Intelligence Corruption System":

  test "disinformation creates ongoing effect with correct duration":
    let config = globalEspionageConfig

    var effects: seq[esp_types.OngoingEffect] = @[]
    let effect = esp_types.OngoingEffect(
      effectType: esp_types.EffectType.IntelCorrupted,
      targetHouse: "house1",
      targetSystem: none(SystemId),
      turnsRemaining: config.effects.disinformation_duration,
      magnitude: 0.3
    )
    effects.add(effect)

    let corruption = hasIntelCorruption(effects, "house1")
    check corruption.isSome
    check corruption.get().turnsRemaining == 2
    check corruption.get().magnitude == 0.3

  test "disinformation does not affect other houses":
    var effects: seq[esp_types.OngoingEffect] = @[]
    let effect = esp_types.OngoingEffect(
      effectType: esp_types.EffectType.IntelCorrupted,
      targetHouse: "house1",
      targetSystem: none(SystemId),
      turnsRemaining: 2,
      magnitude: 0.3
    )
    effects.add(effect)

    let corruption = hasIntelCorruption(effects, "house2")
    check corruption.isNone

  test "expired disinformation returns none":
    var effects: seq[esp_types.OngoingEffect] = @[]
    let effect = esp_types.OngoingEffect(
      effectType: esp_types.EffectType.IntelCorrupted,
      targetHouse: "house1",
      targetSystem: none(SystemId),
      turnsRemaining: 0,  # Expired
      magnitude: 0.3
    )
    effects.add(effect)

    let corruption = hasIntelCorruption(effects, "house1")
    check corruption.isNone

  test "dishonored status creates intelligence corruption":
    let config = globalDiplomacyConfig

    let dishonoredStatus = dip_types.DishonoredStatus(
      active: true,
      turnsRemaining: config.pact_violations.dishonored_status_turns,
      violationTurn: 1
    )

    let corruption = hasDishonoredCorruption(dishonoredStatus)
    check corruption.isSome
    check corruption.get() == config.pact_violations.dishonor_corruption_magnitude
    check corruption.get() == 0.5  # 50% corruption

  test "inactive dishonor returns no corruption":
    let dishonoredStatus = dip_types.DishonoredStatus(
      active: false,
      turnsRemaining: 0,
      violationTurn: 1
    )

    let corruption = hasDishonoredCorruption(dishonoredStatus)
    check corruption.isNone

  test "expired dishonor returns no corruption":
    let dishonoredStatus = dip_types.DishonoredStatus(
      active: true,
      turnsRemaining: 0,  # Expired
      violationTurn: 1
    )

    let corruption = hasDishonoredCorruption(dishonoredStatus)
    check corruption.isNone

suite "Intelligence Corruption - Data Integrity":

  test "corruptInt applies variance correctly":
    var rng = initRand(12345)
    let original = 100

    # Test with 30% corruption
    let corrupted = corruptInt(original, 0.3, rng)

    # Should be within 70-130 range (30% variance)
    check corrupted >= 70
    check corrupted <= 130
    check corrupted != original  # Should be different (statistically)

  test "corruptInt never goes negative":
    var rng = initRand(12345)
    let original = 10

    # Even with high corruption, should not go negative
    let corrupted = corruptInt(original, 0.9, rng)
    check corrupted >= 0

  test "corruptInt with zero value returns zero":
    var rng = initRand(12345)
    let corrupted = corruptInt(0, 0.5, rng)
    check corrupted == 0

  test "fleet intel corruption affects ship counts":
    var rng = initRand(12345)
    let fleet = FleetIntel(
      fleetId: "fleet1",
      owner: "house1",
      location: 1,
      shipCount: 10,
      squadronDetails: none(seq[SquadronIntel])
    )

    let corrupted = corruptFleetIntel(fleet, 0.3, rng)

    # Ship count should be corrupted
    check corrupted.shipCount != fleet.shipCount
    check corrupted.shipCount >= 7  # 30% down
    check corrupted.shipCount <= 13  # 30% up

  test "colony intel corruption affects population and industry":
    var rng = initRand(12345)
    let colony = ColonyIntelReport(
      colonyId: 1,
      targetOwner: "house1",
      gatheredTurn: 1,
      quality: IntelQuality.Perfect,
      population: 1000,
      industry: 500,
      defenses: 100,
      starbaseLevel: 3,
      constructionQueue: @[],
      grossOutput: some(8000),
      taxRevenue: some(4000),
      unassignedSquadronCount: 5,
      reserveFleetCount: 2,
      mothballedFleetCount: 1,
      shipyardCount: 3
    )

    let corrupted = corruptColonyIntel(colony, 0.4, rng)

    # All numeric fields should be corrupted
    check corrupted.population != colony.population
    check corrupted.industry != colony.industry
    check corrupted.defenses != colony.defenses
    check corrupted.starbaseLevel != colony.starbaseLevel
    check corrupted.grossOutput.get() != colony.grossOutput.get()
    check corrupted.taxRevenue.get() != colony.taxRevenue.get()

suite "Intelligence Quality Levels":

  test "visual quality - fleet encounter without tech levels":
    # Visual intelligence from regular fleet encounters
    # Should show ship types but tech levels as 0

    let fleetIntel = FleetIntel(
      fleetId: "enemy-fleet-1",
      owner: "house2",
      location: 1,
      shipCount: 5,
      squadronDetails: some(@[
        SquadronIntel(
          squadronId: "sq1",
          shipClass: "Destroyer",
          shipCount: 3,
          techLevel: 0,  # Visual quality - no tech visible
          hullIntegrity: none(int)  # Visual quality - no damage visible
        ),
        SquadronIntel(
          squadronId: "sq2",
          shipClass: "Cruiser",
          shipCount: 2,
          techLevel: 0,  # Visual quality - no tech visible
          hullIntegrity: none(int)  # Visual quality - no damage visible
        )
      ])
    )

    # Verify visual quality constraints
    check fleetIntel.squadronDetails.isSome
    for squad in fleetIntel.squadronDetails.get():
      check squad.techLevel == 0
      check squad.hullIntegrity.isNone

  test "spy quality - includes tech levels and hull integrity":
    # Spy quality from espionage operations
    # Should include tech levels and damage assessment

    let fleetIntel = FleetIntel(
      fleetId: "enemy-fleet-1",
      owner: "house2",
      location: 1,
      shipCount: 5,
      squadronDetails: some(@[
        SquadronIntel(
          squadronId: "sq1",
          shipClass: "Destroyer",
          shipCount: 3,
          techLevel: 2,  # Spy quality - tech visible
          hullIntegrity: some(85)  # Spy quality - damage visible
        )
      ])
    )

    # Verify spy quality includes details
    check fleetIntel.squadronDetails.isSome
    let squad = fleetIntel.squadronDetails.get()[0]
    check squad.techLevel == 2
    check squad.hullIntegrity.isSome
    check squad.hullIntegrity.get() == 85

  test "perfect quality - scout reports are always accurate":
    # Perfect quality from scouts (before corruption)
    # All details available and accurate

    let colonyIntel = ColonyIntelReport(
      colonyId: 1,
      targetOwner: "house2",
      gatheredTurn: 1,
      quality: IntelQuality.Perfect,
      population: 1000,
      industry: 500,
      defenses: 100,
      starbaseLevel: 3,
      constructionQueue: @["Destroyer", "Cruiser"],  # Queue visible
      grossOutput: some(8000),  # Economic data visible
      taxRevenue: some(4000),   # Economic data visible
      unassignedSquadronCount: 5,
      reserveFleetCount: 2,
      mothballedFleetCount: 1,
      shipyardCount: 3
    )

    # Verify perfect quality includes all details
    check colonyIntel.grossOutput.isSome
    check colonyIntel.taxRevenue.isSome
    check colonyIntel.constructionQueue.len > 0

suite "Intelligence Configuration Integration":

  test "espionage config loads disinformation parameters correctly":
    let config = globalEspionageConfig

    # Verify disinformation config from espionage.kdl
    check config.effects.disinformation_duration == 2
    check config.effects.disinformation_min_variance == 0.2
    check config.effects.disinformation_max_variance == 0.4
    check config.effects.intel_block_duration == 1

  test "diplomacy config loads dishonor parameters correctly":
    let config = globalDiplomacyConfig

    # Verify dishonor config from diplomacy.kdl
    check config.pact_violations.dishonored_status_turns == 3
    check config.pact_violations.dishonor_corruption_magnitude == 0.5

  test "disinformation variance stays within configured bounds":
    let config = globalEspionageConfig
    var rng = initRand(12345)

    # Test that corruption uses configured variance
    let minVariance = config.effects.disinformation_min_variance
    let maxVariance = config.effects.disinformation_max_variance

    # Average of min and max should be around 0.3 (30%)
    let avgVariance = (minVariance + maxVariance) / 2.0
    check abs(avgVariance - 0.3) < 0.0001  # Use approximate equality for floats

    # Test multiple corruptions stay in bounds
    var allInBounds = true
    for i in 0..99:
      let corrupted = corruptInt(100, avgVariance, rng)
      if corrupted < 60 or corrupted > 140:  # 40% is max variance
        allInBounds = false
        break

    check allInBounds

suite "Intelligence Corruption - Strategic Impact":

  test "dishonor corruption is more severe than disinformation":
    let espConfig = globalEspionageConfig
    let dipConfig = globalDiplomacyConfig

    # Dishonor: 50% corruption
    let dishonoredMagnitude = dipConfig.pact_violations.dishonor_corruption_magnitude

    # Disinformation: 20-40% corruption (average 30%)
    let disinfoAvg = (espConfig.effects.disinformation_min_variance +
                      espConfig.effects.disinformation_max_variance) / 2.0

    # Verify dishonor is more severe
    check dishonoredMagnitude > espConfig.effects.disinformation_max_variance
    check dishonoredMagnitude == 0.5
    check abs(disinfoAvg - 0.3) < 0.0001  # Use approximate equality for floats

  test "dishonor lasts longer than disinformation":
    let espConfig = globalEspionageConfig
    let dipConfig = globalDiplomacyConfig

    check dipConfig.pact_violations.dishonored_status_turns == 3
    check espConfig.effects.disinformation_duration == 2
    check dipConfig.pact_violations.dishonored_status_turns > espConfig.effects.disinformation_duration

  test "multiple corruption sources use highest magnitude":
    # When both disinformation and dishonor active, use worst case
    var rng = initRand(12345)

    let dishonoredMag = 0.5  # 50% from dishonor
    let disinfoMag = 0.3     # 30% from disinformation

    # Use highest corruption
    let worstCase = max(dishonoredMag, disinfoMag)
    check worstCase == 0.5

    # Corrupted values should reflect highest corruption
    let corrupted = corruptInt(100, worstCase, rng)
    # With 50% corruption, range is 50-150
    check corrupted >= 50
    check corrupted <= 150

echo "\n✓ Intelligence System Integration Tests Complete"
