## Integration Test for KDL Tech Config Loader
##
## Tests loading config/tech.kdl using the real engine config system
## Verifies all 13 tech sections and cost lookup functions

import std/[options, strutils]
import ../../src/engine/config/tech_config
import ../../src/engine/types/tech

proc main() =
  echo "Testing KDL Tech Config Loader with actual config file..."
  echo "Config path: config/tech.kdl"

  try:
    # Test 1: Load actual config file
    echo "\n[1] Loading via engine config system..."
    let config = loadTechConfig("config/tech.kdl")
    echo "✓ Loaded successfully"

    # Test 2: Verify starting tech levels
    echo "\n[2] Checking starting tech levels..."
    assert config.startingTech.economicLevel == 1
    assert config.startingTech.scienceLevel == 1
    assert config.startingTech.constructionTech == 1
    assert config.startingTech.weaponsTech == 1
    assert config.startingTech.terraformingTech == 1
    assert config.startingTech.electronicIntelligence == 1
    assert config.startingTech.cloakingTech == 1
    assert config.startingTech.shieldTech == 1
    assert config.startingTech.counterIntelligence == 1
    assert config.startingTech.fighterDoctrine == 1
    assert config.startingTech.advancedCarrierOps == 1
    echo "✓ All tech starts at level 1 (critical requirement)"

    # Test 3: Verify economic level progression
    echo "\n[3] Checking economic level costs..."
    assert config.economicLevel.level1Erp == 25
    assert config.economicLevel.level1Mod == 0.05'f32
    assert config.economicLevel.level5Erp == 45
    assert config.economicLevel.level5Mod == 0.25'f32
    assert config.economicLevel.level10Erp == 82
    assert config.economicLevel.level10Mod == 0.50'f32
    assert config.economicLevel.level11Erp == 90
    assert config.economicLevel.level11Mod == 0.50'f32
    echo "✓ EL costs: 25 ERP (5% bonus) → 90 ERP (50% max bonus)"

    # Test 4: Verify science level progression
    echo "\n[4] Checking science level costs..."
    assert config.scienceLevel.level1Srp == 12
    assert config.scienceLevel.level4Srp == 20
    assert config.scienceLevel.level8Srp == 37
    echo "✓ SL costs: 12 SRP → 37 SRP (max SL8)"

    # Test 5: Verify construction tech
    echo "\n[5] Checking construction tech..."
    assert config.constructionTech.capacityMultiplierPerLevel == 0.10'f32
    assert config.constructionTech.level1Trp == 24
    assert config.constructionTech.level5Trp == 44
    assert config.constructionTech.level10Trp == 70
    assert config.constructionTech.level15Trp == 120
    echo "✓ CST costs: 24 TRP → 120 TRP (max CST15)"

    # Test 6: Verify weapons tech
    echo "\n[6] Checking weapons tech..."
    assert config.weaponsTech.weaponsStatIncreasePerLevel == 0.10'f32
    assert config.weaponsTech.weaponsCostIncreasePerLevel == 0.10'f32
    assert config.weaponsTech.level1Trp == 12
    assert config.weaponsTech.level10Trp == 35
    assert config.weaponsTech.level15Trp == 60
    echo "✓ WEP: 10% AS/DS increase, 10% cost increase per level"

    # Test 7: Verify terraforming tech
    echo "\n[7] Checking terraforming tech..."
    assert config.terraformingTech.level1Trp == 12
    assert config.terraformingTech.level1PlanetClass == "Extreme"
    assert config.terraformingTech.level4PlanetClass == "Harsh"
    assert config.terraformingTech.level7Trp == 27
    assert config.terraformingTech.level7PlanetClass == "Eden"
    echo "✓ TER progression: Extreme → Eden (7 levels)"

    # Test 8: Verify terraforming upgrade costs
    echo "\n[8] Checking terraforming upgrade costs..."
    assert config.terraformingUpgradeCosts.extremeTer == 1
    assert config.terraformingUpgradeCosts.extremePp == 0
    assert config.terraformingUpgradeCosts.desolatePp == 60
    assert config.terraformingUpgradeCosts.harshPp == 500
    assert config.terraformingUpgradeCosts.edenPp == 2000
    assert config.terraformingUpgradeCosts.edenPuMax == 999999
    echo "✓ Upgrade costs: 0 PP (extreme) → 2000 PP (eden)"

    # Test 9: Verify electronic intelligence
    echo "\n[9] Checking electronic intelligence..."
    assert config.electronicIntelligence.level1Trp == 12
    assert config.electronicIntelligence.level8Trp == 30
    assert config.electronicIntelligence.level15Trp == 60
    echo "✓ ELI costs: 12 TRP → 60 TRP (max ELI15)"

    # Test 10: Verify cloaking tech
    echo "\n[10] Checking cloaking tech..."
    assert config.cloakingTech.level1Trp == 17
    assert config.cloakingTech.level8Trp == 35
    assert config.cloakingTech.level15Trp == 70
    echo "✓ CLK costs: 17 TRP → 70 TRP (max CLK15)"

    # Test 11: Verify shield tech
    echo "\n[11] Checking shield tech..."
    assert config.shieldTech.level1Trp == 17
    assert config.shieldTech.level6Trp == 30
    assert config.shieldTech.level15Trp == 70
    echo "✓ SLD costs: 17 TRP → 70 TRP (max SLD15)"

    # Test 12: Verify counter intelligence
    echo "\n[12] Checking counter intelligence..."
    assert config.counterIntelligenceTech.level1Trp == 12
    assert config.counterIntelligenceTech.level10Trp == 35
    assert config.counterIntelligenceTech.level15Trp == 60
    echo "✓ CIC costs: 12 TRP → 60 TRP (max CIC15)"

    # Test 13: Verify fighter doctrine
    echo "\n[13] Checking fighter doctrine..."
    assert config.fighterDoctrine.level1Trp == 0
    assert config.fighterDoctrine.level1CapacityMultiplier == 1.0'f32
    assert config.fighterDoctrine.level1Description == "Basic Fighter Operations"
    assert config.fighterDoctrine.level2CapacityMultiplier == 1.5'f32
    assert config.fighterDoctrine.level3CapacityMultiplier == 2.0'f32
    echo "✓ FD: 1.0x → 2.0x capacity (3 levels)"

    # Test 14: Verify advanced carrier operations
    echo "\n[14] Checking advanced carrier operations..."
    assert config.advancedCarrierOperations.capacityMultiplierPerLevel == 0.10'f32
    assert config.advancedCarrierOperations.level1CvCapacity == 3
    assert config.advancedCarrierOperations.level1CxCapacity == 5
    assert config.advancedCarrierOperations.level3CvCapacity == 5
    assert config.advancedCarrierOperations.level3CxCapacity == 8
    echo "✓ ACO: CV 3→5, CX 5→8 (3 levels)"

    # Test 15: Test cost lookup functions
    echo "\n[15] Testing cost lookup functions..."
    assert getELUpgradeCostFromConfig(1) == 25
    assert getELUpgradeCostFromConfig(5) == 45
    assert getELUpgradeCostFromConfig(11) == 90
    echo "✓ getELUpgradeCostFromConfig works"

    assert getSLUpgradeCostFromConfig(1) == 12
    assert getSLUpgradeCostFromConfig(4) == 20
    assert getSLUpgradeCostFromConfig(8) == 37
    echo "✓ getSLUpgradeCostFromConfig works"

    assert getTechUpgradeCostFromConfig(TechField.ConstructionTech, 1) == 24
    assert getTechUpgradeCostFromConfig(TechField.WeaponsTech, 1) == 12
    assert getTechUpgradeCostFromConfig(TechField.TerraformingTech, 7) == 27
    assert getTechUpgradeCostFromConfig(TechField.ElectronicIntelligence, 15) == 60
    assert getTechUpgradeCostFromConfig(TechField.CloakingTech, 1) == 17
    assert getTechUpgradeCostFromConfig(TechField.ShieldTech, 1) == 17
    assert getTechUpgradeCostFromConfig(TechField.CounterIntelligence, 1) == 12
    assert getTechUpgradeCostFromConfig(TechField.FighterDoctrine, 2) == 15
    assert getTechUpgradeCostFromConfig(TechField.AdvancedCarrierOps, 3) == 22
    echo "✓ getTechUpgradeCostFromConfig works for all tech fields"

    # Test 16: Test global config instance
    echo "\n[16] Testing global config instance..."
    assert globalTechConfig.startingTech.economicLevel == 1
    assert globalTechConfig.economicLevel.level1Erp == 25
    echo "✓ globalTechConfig initialized correctly"

    echo "\n" & "=".repeat(60)
    echo "✓ ALL TESTS PASSED - KDL tech config loader working!"
    echo "  - 13 tech sections loaded correctly"
    echo "  - All cost lookup functions verified"
    echo "  - Global config instance initialized"
    echo "=".repeat(60)

  except Exception as e:
    echo "\n✗ TEST FAILED:"
    echo "  Error: ", e.msg
    echo "  Type: ", $e.name
    if e.parent != nil:
      echo "  Parent: ", e.parent.msg
    quit(1)

when isMainModule:
  main()
