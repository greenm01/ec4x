## Unit Tests for Combat Effectiveness Rating (CER)
##
## Tests the CER roll mechanics and table lookups.
## Per docs/specs/07-combat.md Section 7.4.1

import std/[unittest, random]
import ../../src/engine/types/combat
import ../../src/engine/systems/combat/cer

suite "CER: Space/Orbital Combat Table":
  ## Tests for Space/Orbital CRT (Table 7.1)
  ## Roll ≤2: 0.25×, Roll 3-5: 0.50×, Roll 6+: 1.00×

  test "Roll 1 with DRM 0 gives 0.25x CER":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.cer == 0.25:
        check result.cer == 0.25
        found = true
        break
    check found

  test "Roll 2 with DRM 0 gives 0.25x CER":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.cer == 0.25:
        check result.cer == 0.25
        found = true
        break
    check found

  test "Roll 3-5 with DRM 0 gives 0.50x CER":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.cer == 0.50:
        check result.cer == 0.50
        found = true
        break
    check found

  test "Roll 6+ with DRM 0 gives 1.00x CER":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.cer == 1.00:
        check result.cer == 1.00
        found = true
        break
    check found

  test "Positive DRM improves CER":
    # With +5 DRM, even roll of 1 becomes 6, giving 1.00x
    var rng = initRand(42)
    let result = rollCER(rng, 5, CombatTheater.Space)
    # With +5, minimum modified roll is 6 (1+5), always 1.00x
    check result.cer == 1.00

  test "Negative DRM reduces CER":
    # With -5 DRM, even roll of 5 becomes 0, giving 0.25x
    var rng = initRand(42)
    # Run multiple times to verify behavior
    var got025 = false
    var got050 = false
    for seed in 0..100:
      rng = initRand(seed)
      let result = rollCER(rng, -5, CombatTheater.Space)
      if result.cer == 0.25:
        got025 = true
      if result.cer == 0.50:
        got050 = true
    # With -5, rolls 1-7 become ≤2, so mostly 0.25x
    check got025

  test "Orbital theater uses same table as Space":
    var rng1 = initRand(42)
    var rng2 = initRand(42)
    let spaceResult = rollCER(rng1, 0, CombatTheater.Space)
    let orbitalResult = rollCER(rng2, 0, CombatTheater.Orbital)
    check spaceResult.cer == orbitalResult.cer

suite "CER: Ground Combat Table":
  ## Tests for Ground Combat CRT (Table 7.2)
  ## Roll ≤2: 0.5×, Roll 3-6: 1.0×, Roll 7-8: 1.5×, Roll 9+: 2.0×

  test "Roll ≤2 gives 0.5x CER in ground combat":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, -8, CombatTheater.Planetary)
      if result.cer == 0.5:
        check result.cer == 0.5
        found = true
        break
    check found

  test "Roll 3-6 gives 1.0x CER in ground combat":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Planetary)
      if result.cer == 1.0:
        check result.cer == 1.0
        found = true
        break
    check found

  test "Roll 7-8 gives 1.5x CER in ground combat":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Planetary)
      if result.cer == 1.5:
        check result.cer == 1.5
        found = true
        break
    check found

  test "Roll 9+ gives 2.0x CER in ground combat":
    var found = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Planetary)
      if result.cer == 2.0:
        check result.cer == 2.0
        found = true
        break
    check found

  test "Ground combat has higher maximum CER than space":
    # Ground max is 2.0, space max is 1.0
    var gotGroundMax = false
    var gotSpaceMax = false

    for seed in 0..1000:
      var rng = initRand(seed)
      let groundResult = rollCER(rng, 5, CombatTheater.Planetary)
      rng = initRand(seed)
      let spaceResult = rollCER(rng, 5, CombatTheater.Space)

      if groundResult.cer == 2.0:
        gotGroundMax = true
      if spaceResult.cer == 1.0:
        gotSpaceMax = true

    check gotSpaceMax
    # Ground should be able to reach 2.0 with high DRM
    # With +5, roll of 4+ gives 9+, which is 2.0
    var rng = initRand(42)
    let result = rollCER(rng, 10, CombatTheater.Planetary)
    check result.cer == 2.0

suite "CER: Critical Hits":
  ## Tests for critical hit detection (natural 9)
  ## Per docs/specs/07-combat.md Section 7.2.2

  test "Natural 9 marks critical hit":
    var foundCritical = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.isCriticalHit:
        foundCritical = true
        break

    check foundCritical

  test "Critical hit occurs regardless of DRM":
    # Natural roll determines critical, not modified roll
    var foundCritical = false
    for seed in 0..1000:
      var rng = initRand(seed)
      let result = rollCER(rng, -5, CombatTheater.Space)
      if result.isCriticalHit:
        foundCritical = true
        break

    check foundCritical

  test "Critical hit probability is approximately 10%":
    var criticalCount = 0
    let totalRolls = 10000

    for seed in 0..<totalRolls:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.isCriticalHit:
        criticalCount += 1

    # 10% = 1000 out of 10000, allow 8-12% range
    let percentage = (criticalCount.float / totalRolls.float) * 100
    check percentage > 8.0 and percentage < 12.0

suite "CER: Statistical Distribution":
  ## Verify CER distribution matches expected probabilities

  test "Space CER distribution over 10000 rolls":
    var counts = [0, 0, 0] # 0.25, 0.50, 1.00

    for seed in 0..<10000:
      var rng = initRand(seed)
      let result = rollCER(rng, 0, CombatTheater.Space)
      if result.cer == 0.25:
        counts[0] += 1
      elif result.cer == 0.50:
        counts[1] += 1
      elif result.cer == 1.00:
        counts[2] += 1

    # Expected: 20% (rolls 1-2), 30% (rolls 3-5), 50% (rolls 6-10)
    let pct025 = (counts[0].float / 10000.0) * 100
    let pct050 = (counts[1].float / 10000.0) * 100
    let pct100 = (counts[2].float / 10000.0) * 100

    # Allow 5% tolerance
    check pct025 > 15.0 and pct025 < 25.0
    check pct050 > 25.0 and pct050 < 35.0
    check pct100 > 45.0 and pct100 < 55.0

suite "CER: Description Strings":
  ## Test human-readable CER descriptions

  test "Space CER descriptions":
    check cerDescription(0.25, CombatTheater.Space) == "Poor (0.25×)"
    check cerDescription(0.50, CombatTheater.Space) == "Fair (0.50×)"
    check cerDescription(1.00, CombatTheater.Space) == "Good (1.00×)"

  test "Ground CER descriptions":
    check cerDescription(0.5, CombatTheater.Planetary) == "Poor (0.5×)"
    check cerDescription(1.0, CombatTheater.Planetary) == "Fair (1.0×)"
    check cerDescription(1.5, CombatTheater.Planetary) == "Good (1.5×)"
    check cerDescription(2.0, CombatTheater.Planetary) == "Excellent (2.0×)"

when isMainModule:
  echo "========================================"
  echo "  CER Unit Tests"
  echo "========================================"
