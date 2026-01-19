# Daemon Module TODO Audit
**Date:** 2026-01-18
**Scope:** Complete audit of TODOs, SAM pattern implementation, and dead code in `src/daemon/`

---

## Executive Summary

| Category | Count | Status |
|----------|-------|--------|
| TODOs Found | 6 | 3 Obsolete, 3 Active |
| Dead Code Files | 3 | Safe to delete |
| SAM Pattern Violations | 1 | Needs fix |
| TEA References | 2 | Need update to "SAM" |

---

## 1. TODO Classification

### 1.1 ✅ **OBSOLETE - Delete Entirely**

These TODOs are in dead code files that are not imported anywhere:

#### `src/daemon/scheduler.nim:23`
```nim
## TODO: Implement time calculation
```
**Status:** ✅ **Delete** - File is unused stub (35 lines), no imports found
**Action:** Delete entire file

#### `src/daemon/scheduler.nim:28`
```nim
## TODO: Implement scheduling loop that calls onTurnTrigger at configured time
```
**Status:** ✅ **Delete** - Same file as above
**Action:** Delete entire file

#### `src/daemon/processor.nim:25`
```nim
## TODO: Implement NIP-44 decryption and parsing
```
**Status:** ✅ **Delete** - NIP-44 is fully implemented in `transport/nostr/crypto.nim` and used in `daemon.nim:369`
**Action:** Delete entire file (processor.nim is unused)

#### `src/daemon/processor.nim:30`
```nim
## TODO: Implement order validation
```
**Status:** ✅ **Delete** - File is unused stub
**Action:** Delete entire file

#### `src/daemon/processor.nim:35`
```nim
## TODO: Call engine.resolveTurn and return new game state
```
**Status:** ✅ **Delete** - Already implemented in `daemon.nim:175` via `resolveTurnDeterministic`
**Action:** Delete entire file

### 1.2 🔧 **ACTIVE - Complete Implementation**

#### `src/daemon/persistence/writer.nim:485`
```nim
# TODO: Other command types (Research, Espionage, etc.)
```
**Status:** 🔧 **Active** - Partially implemented
**Context:**
- Research/Espionage ARE parsed in `parser/kdl_commands.nim:212-362`
- Command types exist: `ResearchAllocation`, `EspionageAttempt`, `DiplomaticCommand`
- NOT persisted to SQLite yet

**Action Required:**
1. Add persistence for `researchAllocation` (already in CommandPacket)
2. Add persistence for `espionageActions` (already in CommandPacket)
3. Add persistence for `diplomaticCommand` (already in CommandPacket)
4. Add persistence for `ebpInvestment` / `cipInvestment` (already in CommandPacket)

**Estimated Scope:** 4 new INSERT/UPDATE statements in `saveCommandPacket`

#### `src/daemon/persistence/reader.nim:391`
```nim
# TODO: Other command types
```
**Status:** 🔧 **Active** - Mirror of writer.nim:485
**Action Required:**
1. Load `researchAllocation` from DB
2. Load `espionageActions` from DB
3. Load `diplomaticCommand` from DB
4. Load `ebpInvestment` / `cipInvestment` from DB

**Estimated Scope:** 4 new SELECT statements in `loadOrders`

#### `src/daemon/persistence/reader.nim:435`
```nim
# TODO: Load diplomacy, intel, ground units
```
**Status:** 🔧 **Active** - Full state reconstruction
**Context:**
- Currently loads: lanes, houses, colonies, fleets, ships
- Missing: diplomacy state, intel state, ground units (armies/divisions)

**Action Required:**
1. Implement `loadDiplomacy(db, result)` - load diplomatic relationships
2. Implement `loadIntel(db, result)` - load intelligence data
3. Implement `loadGroundUnits(db, result)` - load armies/divisions

**Estimated Scope:** 3 new loader functions + schema for these tables (may already exist)

**Priority Question:** Are these critical for M1/M2 or can they be backlog?

---

## 2. SAM Pattern Analysis

### 2.1 **Core Components**

#### **Proposals** (5 creation sites)
| Function | Line | Purpose |
|----------|------|---------|
| `createGameDiscoveredProposal` | 219-237 | Add game to model |
| `resolveTurnCmd` (success) | 201-208 | Update turn number, clear resolving flag |
| `resolveTurnCmd` (error) | 213-217 | Clear resolving flag on failure |
| `discoverGamesCmd` | 264-275 | Batch game discovery |
| `tickProposal` | 279-314 | Periodic tick + queue discovery |
| `scheduleNextTickCmd` | 317-319 | Sleep delay → tick proposal |

#### **Acceptors** (1 registered)
| Function | Line | Purpose |
|----------|------|---------|
| Generic acceptor | 509-515 | Execute all proposal payloads |

**Pattern:** Single generic acceptor executes all proposal payloads. This is valid for simple use cases but could be split into specific acceptors for clarity.

#### **Reactors** (0 registered)
**Status:** ⚠️ **No reactors registered**
**Impact:** Reactors are part of SAM core (sam_core.nim:73-76) but never used
**Question:** Is this intentional? Should side effects (queueCmd) happen in reactors?

**Current Pattern:**
- Side effects (queueCmd) happen **inside proposal payloads** (e.g., tickProposal:285, 313)
- This works but deviates from strict SAM where reactors handle side effects

**Recommendation:** Document this as "simplified SAM" or refactor to use reactors

#### **Cmd Functions** (3 async effects)
| Function | Line | Returns | Purpose |
|----------|------|---------|---------|
| `resolveTurnCmd` | 160-217 | Future[Proposal] | Load state → resolve turn → save → publish |
| `discoverGamesCmd` | 239-275 | Future[Proposal] | Scan filesystem for game DBs |
| `scheduleNextTickCmd` | 316-319 | Future[Proposal] | Sleep → tick |

**Pattern:** ✅ All Cmds return `Future[Proposal[DaemonModel]]` as expected

### 2.2 **SAM Pattern Violations**

#### ❌ **Violation 1: Model Mutation in Cmd**
**Location:** `daemon.nim:165`
**Code:**
```nim
proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Resolving turn for game: ", gameId)

    # Mark as resolving
    daemonLoop.model.resolving.incl(gameId)  # ❌ VIOLATION
```

**Problem:** Direct model mutation outside of acceptor/proposal payload
**Impact:** Breaks SAM invariant that only acceptors mutate model

**Fix Required:**
1. Move `resolving.incl(gameId)` into a proposal payload
2. Present that proposal BEFORE queueing the async work
3. Or queue a "mark_resolving" proposal at the start of the Cmd

**Recommended Fix:**
```nim
proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Resolving turn for game: ", gameId)

    # No model mutation here!
    try:
      let gameInfo = daemonLoop.model.games[gameId]  # Read-only

      # ... rest of logic

      return Proposal[DaemonModel](
        name: "turn_resolved",
        payload: proc(model: var DaemonModel) =
          model.games[gameId].turn = state.turn
          model.games[gameId].turnDeadline = nextDeadline
          model.resolving.excl(gameId)  # ✅ Mutation in payload
          model.pendingOrders[gameId] = 0
      )
```

And add a new proposal at call site:
```nim
# In checkAndTriggerResolution or checkDeadlineResolution:
daemonLoop.present(Proposal[DaemonModel](
  name: "mark_resolving",
  payload: proc(m: var DaemonModel) =
    m.resolving.incl(gameId)
))
daemonLoop.queueCmd(resolveTurnCmd(gameId))
```

#### ⚠️ **Potential Violation: Model Reads in tickProposal**
**Location:** `daemon.nim:297-298`
**Code:**
```nim
payload: proc(model: var DaemonModel) =
  # ...
  if model.turnDeadlineMinutes > 0 and gameInfo.phase == "Active" and
      gameInfo.turnDeadline.isNone:
    let deadline = calculateTurnDeadline(model.turnDeadlineMinutes)
    updateTurnDeadline(gameInfo.dbPath, gameInfo.id, deadline)  # I/O in payload!
    model.games[gameId].turnDeadline = deadline
```

**Problem:** `updateTurnDeadline` performs I/O (SQLite write) inside acceptor
**Impact:** Violates "acceptors should be pure mutations" principle
**Severity:** Medium - works but not idiomatic SAM

**Recommendation:** Move I/O to Cmd, only mutate model in payload

---

## 3. Dead Code Inventory

### 3.1 **Safe to Delete**

All three files have **zero imports** across the codebase (verified via Grep):

| File | Lines | Last Purpose | Imports Found |
|------|-------|--------------|---------------|
| `src/daemon/scheduler.nim` | 35 | Stub for future scheduling | 0 |
| `src/daemon/processor.nim` | 37 | Stub for order processing | 0 |
| `src/daemon/cmds.nim` | 22 | Old Cmd syntax prototype | 0 |

**cmds.nim Analysis:**
- Uses outdated syntax: `() => async:` (not valid Nim)
- Functionality moved to `daemon.nim:160-217` (resolveTurnCmd)
- No test dependencies (verified: no test files reference it)

**Git History Context:**
```bash
git log --oneline --all -- src/daemon/scheduler.nim
git log --oneline --all -- src/daemon/processor.nim
git log --oneline --all -- src/daemon/cmds.nim
```
_(Recommendation: Check if these were placeholders or abandoned experiments)_

**Decision:** ✅ **Safe to delete all three files**

---

## 4. Terminology Fixes

### 4.1 **TEA → SAM References**

| File | Line | Current Text | Fix |
|------|------|--------------|-----|
| `src/daemon/daemon.nim` | 74 | `# TEA Commands (Async Effects)` | `# SAM Commands (Async Effects)` |
| `src/daemon/README.md` | 9 | `- **Milestone 4:** Refactor to TEA pattern` | `- **Milestone 4:** Refactor to SAM pattern` |

**Context:** Project originally planned TEA (The Elm Architecture) but implemented SAM (State-Action-Model)

---

## 5. Documentation Gaps

### 5.1 **Missing SAM Documentation**

**Current State:**
- SAM implementation exists (sam_core.nim + daemon.nim)
- No architecture documentation explaining SAM
- No examples of SAM patterns
- Confusion between TEA and SAM in comments

**Required Documentation:**
1. `docs/architecture/daemon-sam.md` - Full SAM guide (see Phase 2 of roadmap)
2. Update `docs/architecture/daemon.md` - Add SAM section
3. Rewrite `src/daemon/README.md` - Explain SAM, link to docs

### 5.2 **Undocumented Functions**

Missing doc comments:
- `sam_core.nim:present()` - Queue proposal for processing
- `sam_core.nim:queueCmd()` - Queue async Cmd
- `sam_core.nim:process()` - Main SAM loop iteration
- `daemon.nim:resolveTurnCmd()` - Turn resolution Cmd

---

## 6. Recommendations

### 6.1 **Immediate Actions (Required)**

1. **Fix SAM Violation**
   - [ ] Move `resolving.incl(gameId)` out of Cmd into proposal
   - [ ] Add "mark_resolving" proposal at call sites

2. **Delete Dead Code**
   - [ ] Delete `scheduler.nim`
   - [ ] Delete `processor.nim`
   - [ ] Delete `cmds.nim`
   - [ ] Update git history notes (optional)

3. **Fix TEA References**
   - [ ] Change "TEA" to "SAM" in daemon.nim:74
   - [ ] Change "TEA" to "SAM" in README.md:9

### 6.2 **TODO Completion (Short-term)**

Priority 1 (Critical for turn resolution):
- [ ] Complete `writer.nim:485` - Persist research/espionage/diplomacy commands
- [ ] Complete `reader.nim:391` - Load research/espionage/diplomacy commands

Priority 2 (Full state reconstruction):
- [ ] Complete `reader.nim:435` - Load diplomacy/intel/ground units state
- [ ] **Question for User:** Are diplomacy/intel/ground units needed for M1/M2?

### 6.3 **Architecture Decisions (Clarify)**

1. **Reactor Pattern:**
   - Current: Side effects in proposal payloads
   - SAM Standard: Side effects in reactors
   - **Decision:** Document as "simplified SAM" or refactor to use reactors?

2. **Acceptor Pattern:**
   - Current: Single generic acceptor
   - Alternative: Specific acceptors per proposal type
   - **Decision:** Keep generic or split for clarity?

3. **I/O in Payloads:**
   - Current: Some payloads do I/O (updateTurnDeadline)
   - Best Practice: Payloads should be pure mutations
   - **Decision:** Move I/O to Cmds or document as acceptable?

---

## 7. Next Steps

**Phase 1 (Research) Complete ✅**
- [x] Deep TODO audit
- [x] SAM pattern analysis
- [x] Dead code inventory

**Phase 2 (Documentation) - Ready to Start**
- [ ] Create `daemon-sam.md` with full SAM guide
- [ ] Update `daemon.md` architecture overview
- [ ] Rewrite `README.md` with SAM focus
- [ ] Add Mermaid diagrams (SAM flow, lifecycle, turn resolution)

**Phase 3 (Code Cleanup) - Blocked on User Approval**
- [ ] Get approval to delete dead files
- [ ] Fix SAM violation (model mutation in Cmd)
- [ ] Fix TEA → SAM references
- [ ] Add doc comments to key functions

**Phase 4 (TODO Completion) - Needs Priority Clarification**
- [ ] User: Are diplomacy/intel/ground units needed for current milestone?
- [ ] Complete persistence TODOs based on priority
- [ ] Test full state save/load cycle

---

## Appendix A: SAM Flow Diagram (Current Implementation)

```
┌─────────────────────────────────────────────────────────────────┐
│                         External Event                          │
│              (Nostr, Tick, Manual CLI Command)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   queueCmd(Cmd)      │
                    │   or present(Prop)   │
                    └──────────┬───────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
                ▼                             ▼
    ┌──────────────────────┐      ┌──────────────────────┐
    │   Cmd (async work)   │      │  Proposal (queued)   │
    │  - Load from DB      │      └──────────┬───────────┘
    │  - Resolve turn      │                 │
    │  - Publish results   │                 │
    └──────────┬───────────┘                 │
               │                             │
               │ Returns                     │
               ▼                             │
    ┌──────────────────────┐                 │
    │  Proposal (queued)   │                 │
    └──────────┬───────────┘                 │
               │                             │
               └──────────────┬──────────────┘
                              │
                              ▼
                   ┌────────────────────────┐
                   │   daemonLoop.process() │
                   │   (Main SAM Loop)      │
                   └──────────┬─────────────┘
                              │
                              ▼
                   ┌────────────────────────┐
                   │   Acceptor             │
                   │   (Execute payloads)   │
                   │   ✅ MUTATE MODEL      │
                   └──────────┬─────────────┘
                              │
                              ▼
                   ┌────────────────────────┐
                   │   Reactor (unused)     │
                   │   ⚠️ Not implemented   │
                   └────────────────────────┘
```

**Note:** Current implementation queues new Cmds inside proposal payloads, which works but deviates from strict SAM where reactors handle side effects.

---

**End of Audit Report**
