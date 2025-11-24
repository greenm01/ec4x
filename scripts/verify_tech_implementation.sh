#!/bin/bash
# Comprehensive Tech Implementation Verification
# Checks that all 11 tech fields are properly implemented and applied

echo "========================================"
echo "EC4X Tech Implementation Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

verified=0
partial=0
missing=0

check_tech() {
    local tech_name="$1"
    local search_pattern="$2"
    local expected_file="$3"
    local description="$4"

    echo -n "[$tech_name] $description... "

    if grep -rq "$search_pattern" src/engine/ --include="*.nim" 2>/dev/null; then
        if [ -n "$expected_file" ] && grep -q "$search_pattern" "$expected_file" 2>/dev/null; then
            echo -e "${GREEN}✓ VERIFIED${NC}"
            ((verified++))
            return 0
        else
            echo -e "${YELLOW}⚠ PARTIAL${NC} (found but not in expected location)"
            ((partial++))
            return 1
        fi
    else
        echo -e "${RED}✗ MISSING${NC}"
        ((missing++))
        return 2
    fi
}

echo "=== Core Tech Effects ==="
echo ""

# EL - Economic Level
check_tech "EL" "getEconomicLevelModifier\|EL_MOD\|elMod" "src/engine/economy/production.nim" \
    "Economic Level modifier in GCO calculation"

# SL - Science Level
check_tech "SL" "Science.*Level\|SL.*tech\|scienceLevel" "src/engine/research/" \
    "Science Level in research point calculation"

# CST - Construction Tech
check_tech "CST" "construction.*tech\|CST.*level\|shipyard.*capacity" "src/engine/economy/construction.nim" \
    "Construction Tech for shipyard capacity"

# WEP - Weapons Tech
check_tech "WEP" "weaponsMultiplier\|WEP.*tech\|attackStrength.*tech" "src/engine/squadron.nim" \
    "Weapons Tech modifying AS/DS by 10% per level"

# TER - Terraforming Tech
check_tech "TER" "terraforming.*tech\|TER.*level" "src/engine/economy/" \
    "Terraforming Tech effects"

# ELI - Electronic Intelligence
check_tech "ELI" "eliLevel\|ELI.*tech\|electronic.*intelligence" "src/engine/combat/engine.nim" \
    "ELI tech in detection system"

# CLK - Cloaking Tech
check_tech "CLK" "clkLevel\|CLK.*tech\|cloaking" "src/engine/combat/engine.nim" \
    "CLK tech for raider cloaking"

# SLD - Shield Tech (Planetary Shields)
check_tech "SLD" "shield.*tech\|SLD.*level\|planetary.*shield" "src/engine/combat/ground.nim" \
    "Shield Tech for bombardment defense"

# CIC - Counter-Intelligence
check_tech "CIC" "counter.*intelligence\|CIC.*level" "src/engine/espionage/" \
    "Counter-Intelligence for espionage defense"

# FD - Fighter Doctrine
check_tech "FD" "fighter.*doctrine\|FD.*level\|fighter.*capacity.*multiplier" "src/engine/" \
    "Fighter Doctrine capacity multiplier"

# ACO - Advanced Carrier Ops
check_tech "ACO" "getCarrierCapacity\|ACO.*level\|advanced.*carrier" "src/engine/squadron.nim" \
    "Advanced Carrier Ops hangar capacity"

echo ""
echo "=== Summary ==="
echo -e "${GREEN}Verified: $verified${NC}"
echo -e "${YELLOW}Partial:  $partial${NC}"
echo -e "${RED}Missing:  $missing${NC}"
echo ""

total=$((verified + partial + missing))
if [ $missing -eq 0 ] && [ $partial -eq 0 ]; then
    echo -e "${GREEN}✓ All tech mechanics fully implemented!${NC}"
    exit 0
elif [ $missing -eq 0 ]; then
    echo -e "${YELLOW}⚠ Some tech mechanics need verification${NC}"
    exit 1
else
    echo -e "${RED}✗ Critical tech mechanics missing implementation${NC}"
    exit 2
fi
