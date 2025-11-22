## Quick Economy Verification Test
import ../src/engine/economy/production
import ../src/common/types/planets

echo "=== Economy Spec Verification ==="
echo ""

# Test RAW INDEX values (from economy.md table)
echo "RAW INDEX Test:"
let eden_veryrich = getRawIndex(PlanetClass.Eden, ResourceRating.VeryRich)
echo "  Eden + Very Rich: ", eden_veryrich, " (expect 1.40)"
assert eden_veryrich == 1.40, "Eden Very Rich should be 140%"

let extreme_verypoor = getRawIndex(PlanetClass.Extreme, ResourceRating.VeryPoor)
echo "  Extreme + Very Poor: ", extreme_verypoor, " (expect 0.60)"
assert extreme_verypoor == 0.60, "Extreme Very Poor should be 60%"

let benign_abundant = getRawIndex(PlanetClass.Benign, ResourceRating.Abundant)
echo "  Benign + Abundant: ", benign_abundant, " (expect 0.80)"
assert benign_abundant == 0.80, "Benign Abundant should be 80%"

echo "  ✅ RAW INDEX correct"
echo ""

# Test EL_MOD (from economy.md:4.2 - "5% per level")
echo "EL_MOD Test:"
let el1_mod = getEconomicLevelModifier(1)
echo "  EL1: ", el1_mod, " (expect 1.05)"
assert el1_mod == 1.05, "EL1 should give 5% bonus"

let el5_mod = getEconomicLevelModifier(5)
echo "  EL5: ", el5_mod, " (expect 1.25)"
assert el5_mod == 1.25, "EL5 should give 25% bonus"

let el10_mod = getEconomicLevelModifier(10)
echo "  EL10: ", el10_mod, " (expect 1.50)"
assert el10_mod == 1.50, "EL10 should give 50% bonus"

echo "  ✅ EL_MOD correct"
echo ""

# Test PROD_GROWTH curve
echo "PROD_GROWTH Test:"
let tax0_growth = getProductivityGrowth(0)
echo "  Tax 0%: ", tax0_growth, " (expect ~0.10)"

let tax50_growth = getProductivityGrowth(50)
echo "  Tax 50%: ", tax50_growth, " (expect 0.00)"
assert tax50_growth == 0.0, "50% tax should give 0% growth"

let tax100_growth = getProductivityGrowth(100)
echo "  Tax 100%: ", tax100_growth, " (expect ~-0.10)"

echo "  ✅ PROD_GROWTH working"
echo ""

echo "=== All Economy Formulas Match Spec ==="
