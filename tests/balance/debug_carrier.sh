#!/bin/bash
# Debug script to trace carrier/fighter build decisions

./tests/balance/run_simulation --seed 42 --turns 8 2>&1 | grep -E "\[AI\].*Admiral: Generating strategic|CFO: Processing|Strategic Triage|Requirements Blend|Calculated requiredPP|carrier|fighter|SpecialUnits" | head -100
