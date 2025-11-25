# Fog of War Integration Status

## ✅ Completed

1. **Core fog-of-war system** (`src/engine/fog_of_war.nim`)
   - `FilteredGameState` type - AI view with limited visibility
   - `createFogOfWarView()` - Filter full GameState for specific house
   - Visibility levels: Owned, Occupied, Scouted, Adjacent, None
   - Helper functions: `canSeeColonyDetails()`, `canSeeFleets()`, `getIntelStaleness()`

2. **Visibility rules implemented:**
   - Owned systems: Full details where house has colonies
   - Occupied systems: Full details where house has fleets
   - Scouted systems: Stale intel from intelligence database
   - Adjacent systems: Awareness only (system exists, no details)
   - Hidden systems: No visibility at all

3. **Integration with intelligence system:**
   - Uses existing `IntelligenceDatabase` for stale intel
   - Tracks last-seen turns for staleness calculation
   - Supports colony reports and system reports from spy scouts

## ⏳ TODO: Phase 2 RBA Improvements with FoW

### High Priority

**Task: Refactor ai_controller.nim to use FilteredGameState**

Current situation:
- `generateAIOrders*(controller: var AIController, state: GameState, rng: var Rand)` receives full game state
- All helper functions (175+ lines each) directly access `state.colonies`, `state.fleets`, `state.houses`
- AI has perfect information - sees all enemy positions, colonies, fleets

Required changes:

#### 1. Change AI entry point signature
```nim
# OLD:
proc generateAIOrders*(controller: var AIController, state: GameState, rng: var Rand): OrderPacket

# NEW:
proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket
```

#### 2. Update simulation runner
```nim
# In run_simulation.nim, line ~52
for controller in controllers.mitems:
  # Add fog-of-war filtering
  let filteredView = createFogOfWarView(game, controller.houseId)
  let orders = controller.generateAIOrders(filteredView, rng)
  allOrders.add(orders)
```

#### 3. Refactor all helper functions

**Helper functions that need FoW updates:** (25+ functions)

- `getOwnedColonies(state: GameState, houseId)` → Use `filtered.ownColonies`
- `getOwnedFleets(state: GameState, houseId)` → Use `filtered.ownFleets`
- `findNearestUncolonizedSystem(state, fromSystem)` → Use `filtered.visibleSystems`, check visibility
- `findWeakestEnemyColony(state, houseId, rng)` → Use `filtered.visibleColonies`
- `assessCombatSituation(controller, state, systemId)` → Use `filtered.visibleFleets`
- `assessDiplomaticSituation(controller, state, targetHouse)` → Use `filtered.houseDiplomacy`
- `calculateMilitaryStrength(state, houseId)` → Use `filtered.visibleFleets` (enemy strength unknown!)
- `calculateEconomicStrength(state, houseId)` → Use `filtered.visibleColonies` (enemy economy estimated!)

**Critical insight:** Many functions will need to return `Option[T]` because AI may not have intel:
```nim
# OLD: Always returns a value (cheating)
proc findWeakestEnemyColony(state: GameState, houseId: HouseId): Option[SystemId]

# NEW: May return none if no intel available
proc findWeakestEnemyColony(filtered: FilteredGameState): Option[SystemId]
```

#### 4. Handle incomplete information

**Example: Fleet assessment with fog-of-war**
```nim
proc assessFleetStrength(filtered: FilteredGameState, systemId: SystemId): int =
  ## Assess enemy fleet strength in a system
  ## Returns 0 if no intel available

  if not filtered.canSeeFleets(systemId):
    return 0  # No visibility - assume no fleet

  var strength = 0
  for visFleet in filtered.visibleFleets:
    if visFleet.location == systemId:
      if visFleet.fullDetails.isSome:
        # Own fleet - full details
        let fleet = visFleet.fullDetails.get
        for squadron in fleet.squadrons:
          strength += calculateSquadronValue(squadron)
      elif visFleet.estimatedShipCount.isSome:
        # Enemy fleet - estimated strength
        strength += visFleet.estimatedShipCount.get * 100  # Rough estimate

  return strength
```

### Medium Priority

**Task: Add intelligence-gathering behavior to RBA**

The RBA currently doesn't prioritize scouting because it has perfect information. With FoW:

1. **Scout deployment priorities:**
   - Adjacent systems (VisibilityLevel.Adjacent) → Send scouts to reveal
   - Stale intel (staleness > 5 turns) → Re-scout for updated intel
   - Enemy borders → Maintain scout coverage

2. **Espionage mission targeting:**
   - SpyOnPlanet: Target enemy colonies with no recent intel
   - SpyOnSystem: Target systems with suspected enemy fleets
   - HackStarbase: Target major enemy production centers

3. **Update helper functions:**
```nim
proc identifyScoutingTargets(filtered: FilteredGameState): seq[SystemId] =
  ## Find systems that need scouting
  result = @[]

  for systemId, vis in filtered.visibleSystems:
    if vis.visibility == VisibilityLevel.Adjacent:
      # Unknown system - high priority
      result.add(systemId)
    elif vis.visibility == VisibilityLevel.Scouted:
      let staleness = filtered.getIntelStaleness(systemId)
      if staleness > 5:
        # Stale intel - medium priority
        result.add(systemId)
```

### Low Priority

**Task: Add test coverage for FoW behaviors**

Create integration tests:
- `tests/integration/test_ai_fog_of_war.nim`
- Scenarios:
  - AI discovers enemy colony after scouting
  - AI reacts to stale intel vs current intel
  - AI prioritizes scouting over expansion when information-starved
  - AI correctly estimates enemy strength from partial intel

## Integration Checklist

- [x] Implement `fog_of_war.nim` module
- [x] Create `FilteredGameState` type
- [x] Implement visibility rules (Owned/Occupied/Scouted/Adjacent/None)
- [x] Integrate with intelligence database
- [ ] Refactor `generateAIOrders()` to accept `FilteredGameState`
- [ ] Update simulation runner to apply FoW filtering
- [ ] Refactor all helper functions (25+ functions)
- [ ] Add intelligence-gathering behavior
- [ ] Handle incomplete information gracefully
- [ ] Test FoW integration with existing balance tests
- [ ] Add FoW-specific integration tests

## Estimated Effort

- Refactoring ai_controller.nim: ~800 lines affected, 50+ function signatures
- Adding intelligence-gathering: ~300 new lines
- Testing and validation: ~200 lines of tests
- **Total: ~1,300 lines changed/added, approximately 2-3 work sessions**

## Notes

- **Critical:** All Phase 2 AI improvements MUST be done with FoW active
- Bootstrap training data (Phase 3) depends on FoW being implemented
- Without FoW, neural network will learn to cheat (expect perfect information)
- Grok feedback: "Perfect information breaks scouting, ELI/CLK, espionage, and Raider mechanics"

---

**Status:** Core FoW system complete ✅ | AI integration pending ⏳ | Ready for Phase 2 implementation 🚀
