# AI Architecture TODOs

## Diagnostics Module Refactor

**Priority**: Medium
**Effort**: Medium (~2-4 hours)

### Problem

The `src/ai/analysis/diagnostics.nim` module currently tracks event counts by directly parsing `GameEvent.eventType` enums and incrementing counters. This approach has several issues:

1. **Fragile**: Adding new event types requires updating diagnostics manually
2. **Not DRY**: Event type knowledge is duplicated (event_factory + diagnostics)
3. **Inconsistent**: Some events tracked, others not (depends on manual updates)
4. **Maintenance burden**: Easy to forget updating diagnostics when adding events

### Solution

Refactor diagnostics to use a **unified event tracking system** based on `event_factory`:

```nim
# Instead of:
if event.eventType == GameEventType.OrderCompleted:
  metrics.ordersCompleted += 1
if event.eventType == GameEventType.OrderFailed:
  metrics.ordersFailed += 1
# ... 84 event types ...

# Use event factory metadata:
import event_factory/metadata  # New module

proc trackEvent(metrics: var Metrics, event: GameEvent) =
  let category = event_factory.getEventCategory(event.eventType)
  case category
  of EventCategory.Order:
    trackOrderEvent(metrics, event)
  of EventCategory.Combat:
    trackCombatEvent(metrics, event)
  of EventCategory.Economic:
    trackEconomicEvent(metrics, event)
  # ...
```

### Benefits

- **Automatic tracking**: New events automatically tracked based on category
- **Single source of truth**: Event metadata in event_factory
- **Easier to maintain**: Add event factory function → tracking works automatically
- **Better organization**: Events grouped by domain (orders, combat, economy, etc.)

### Implementation Steps

1. Create `src/engine/resolution/event_factory/metadata.nim`:
   - Define `EventCategory` enum (Order, Combat, Economic, Intel, Diplomatic)
   - Define `getEventCategory(eventType: GameEventType): EventCategory`
   - Map all 84+ event types to categories

2. Refactor `src/ai/analysis/diagnostics.nim`:
   - Replace direct eventType matching with category-based tracking
   - Keep existing CSV column names for backwards compatibility
   - Add new columns for event subcategories if needed

3. Update tests:
   - Ensure CSV diagnostics still output same columns
   - Verify event counts match pre-refactor values

### Files to Modify

- `src/engine/resolution/event_factory/metadata.nim` (NEW)
- `src/ai/analysis/diagnostics.nim` (REFACTOR)
- `tests/integration/test_comprehensive_mock_game.nim` (UPDATE if needed)

### Related Work

- See `docs/engine/architecture/active_fleet_order_game_events.md` for complete event matrix
- Current implementation: 77/84 fleet order events completed (92%)
- Event factory functions: `orderIssued()`, `orderCompleted()`, `orderFailed()`, `orderAborted()`

---

**Created**: 2025-12-08
**Status**: Not Started
