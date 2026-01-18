# Testing Auto-Resolve Turn Resolution

This guide walks through testing the automatic turn resolution feature that triggers when all human players submit their commands.

## Quick Test (Automated)

```bash
# Run all daemon tests including auto-resolve
nimble testDaemon

# Or run just auto-resolve tests
nim c -r tests/daemon/test_auto_resolve.nim
```

**Expected:** All 15 tests pass ✅

---

## Manual E2E Test Scenario

### Prerequisites

1. **Build all binaries:**
   ```bash
   nimble buildAll
   ```

2. **Start a local Nostr relay** (optional, for full Nostr testing):
   ```bash
   # If you have nostr-rs-relay installed:
   cd ~/dev/nostr-rs-relay
   ./target/release/nostr-rs-relay &
   ```

3. **Create a test game:**
   ```bash
   # Create a 2-player game
   ./bin/ec4x new --name "Auto-Resolve Test" --players 2 --setup scenarios/standard-4-player.kdl

   # Note the game ID from output
   export GAME_ID="<game-id-from-output>"
   ```

### Scenario 1: Local File-Based Auto-Resolve (Simpler)

This tests the auto-resolve logic without requiring Nostr infrastructure.

#### Step 1: Setup Game with Human Players

```bash
# Update database to assign pubkeys to 2 houses (marks them as human)
sqlite3 "data/games/$GAME_ID/ec4x.db" << EOF
UPDATE houses SET nostr_pubkey = 'test-pubkey-alpha' WHERE id = '1';
UPDATE houses SET nostr_pubkey = 'test-pubkey-beta' WHERE id = '2';
UPDATE games SET phase = 'Active' WHERE id = '$GAME_ID';
EOF
```

#### Step 2: Start Daemon with Logging

```bash
# Start daemon in one terminal
./bin/ec4x-daemon start 2>&1 | tee daemon.log
```

**Expected logs:**
```
[INFO] Daemon: Starting EC4X daemon
[INFO] Daemon: Discovered game: <game-id>
```

#### Step 3: Submit Commands (Simulate Players)

**Terminal 2 - Player 1:**
```bash
# Create command packet for House 1
cat > /tmp/player1_commands.kdl << 'EOF'
orders turn=1 house=1 {
  fleet 1 {
    hold
  }
}
EOF

# Simulate command submission via database
sqlite3 "data/games/$GAME_ID/ec4x.db" << EOF
INSERT INTO commands (game_id, house_id, turn, fleet_id, command_type, submitted_at, processed)
VALUES ('$GAME_ID', '1', 1, '1', 'Hold', unixepoch(), 0);
EOF
```

**Check daemon logs:**
```
[DEBUG] Daemon: Turn readiness check: 1/2 players submitted for game=<game-id> turn=1
[DEBUG] Daemon: Waiting for 1 more player(s) for turn 1
```

**Terminal 3 - Player 2:**
```bash
# Submit for House 2
sqlite3 "data/games/$GAME_ID/ec4x.db" << EOF
INSERT INTO commands (game_id, house_id, turn, fleet_id, command_type, submitted_at, processed)
VALUES ('$GAME_ID', '2', 1, '2', 'Hold', unixepoch(), 0);
EOF
```

**Check daemon logs immediately:**
```
[DEBUG] Daemon: Turn readiness check: 2/2 players submitted for game=<game-id> turn=1
[INFO] Daemon: All players submitted! Auto-triggering resolution for game=<game-id> turn=1
[INFO] Daemon: Resolving turn for game: <game-id>
[INFO] Daemon: Publishing turn results for house 1
[INFO] Daemon: Publishing turn results for house 2
```

**Verify turn advanced:**
```bash
sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT turn FROM games;"
# Should output: 2
```

### Scenario 2: Full Nostr E2E Test

This tests the complete flow with TUI clients and Nostr relay.

#### Prerequisites

1. Local Nostr relay running on `ws://localhost:8080`
2. Two TUI client instances

#### Step 1: Create Game via Moderator

```bash
./bin/ec4x new --name "Nostr Test" --players 2 --transport nostr
export GAME_ID="<game-id-from-output>"
```

#### Step 2: Generate Invite Codes

```bash
./bin/ec4x invite --game-id $GAME_ID --count 2

# Note the two invite codes:
# - INVITE_CODE_1
# - INVITE_CODE_2
```

#### Step 3: Start Daemon

```bash
# Terminal 1
./bin/ec4x-daemon start --relay ws://localhost:8080 2>&1 | tee daemon.log
```

**Expected:**
```
[INFO] Nostr: Connecting to ws://localhost:8080
[INFO] Nostr: Connected
[INFO] Daemon: Subscribed to game commands for game=<game-id>
```

#### Step 4: Join as Player 1

```bash
# Terminal 2
./bin/ec4x-tui
```

In TUI:
1. Set relay URL: `ws://localhost:8080`
2. Connect
3. Paste `INVITE_CODE_1`
4. Submit join

**Check daemon logs:**
```
[INFO] Nostr: Slot claimed for game=<game-id> house=1 player=npub...
[INFO] Daemon: Publishing full state for house 1
```

**Check TUI:** Should transition to in-game view with full state

#### Step 5: Join as Player 2

```bash
# Terminal 3
./bin/ec4x-tui
```

Same steps with `INVITE_CODE_2`

**Check daemon logs:**
```
[INFO] Nostr: Slot claimed for game=<game-id> house=2 player=npub...
[INFO] Daemon: Publishing full state for house 2
```

#### Step 6: Submit Orders (Both Players)

**Player 1 (Terminal 2):**
1. Select fleet
2. Issue Hold command
3. Press `Enter Orders` or submit key

**Check daemon logs:**
```
[INFO] Nostr: Received and saved commands for game=<game-id> turn=1 house=1
[DEBUG] Daemon: Turn readiness check: 1/2 players submitted...
[DEBUG] Daemon: Waiting for 1 more player(s) for turn 1
```

**Player 2 (Terminal 3):**
1. Select fleet
2. Issue Hold command
3. Submit orders

**Check daemon logs IMMEDIATELY:**
```
[INFO] Nostr: Received and saved commands for game=<game-id> turn=1 house=2
[DEBUG] Daemon: Turn readiness check: 2/2 players submitted...
[INFO] Daemon: All players submitted! Auto-triggering resolution for game=<game-id> turn=1
[INFO] Daemon: Resolving turn for game: <game-id>
[INFO] Daemon: Publishing turn results for house 1
[INFO] Daemon: Publishing turn results for house 2
```

**Check both TUIs:**
- Should receive delta events (30403)
- Turn counter should advance to 2
- Can submit orders for turn 2

---

## Verification Checklist

### ✅ Core Functionality

- [ ] Daemon counts expected players correctly (only houses with pubkeys)
- [ ] Daemon tracks submitted commands per turn
- [ ] Auto-resolve triggers when all players submit
- [ ] Turn advances after resolution
- [ ] Commands marked as processed after resolution
- [ ] Deltas published to all players

### ✅ Edge Cases

- [ ] **Turn mismatch:** Submitting for wrong turn is rejected with warning
  ```bash
  # Submit for turn 5 when game is on turn 1
  # Expected log: [WARN] Nostr: Command for wrong turn: event has turn=5 but game is on turn=1 - ignoring
  ```

- [ ] **Non-Active phase:** Setup/Paused games don't auto-resolve
  ```bash
  sqlite3 "data/games/$GAME_ID/ec4x.db" "UPDATE games SET phase = 'Setup';"
  # Submit all commands
  # Expected: NO auto-resolve, game stays on same turn
  ```

- [ ] **Partial submissions:** 1/2 players doesn't trigger
  ```
  # Only Player 1 submits
  # Expected log: [DEBUG] Daemon: Waiting for 1 more player(s) for turn 1
  ```

- [ ] **Resubmission:** Player updates commands before resolution
  ```
  # Player 1 submits Hold
  # Player 1 resubmits Move (before Player 2)
  # Expected: Still counts as 1 submission, latest command used
  ```

- [ ] **Concurrent submission:** Both players submit simultaneously
  ```
  # Both submit within milliseconds
  # Expected: One triggers resolution, other gets guard
  # Log: [WARN] Daemon: Turn already resolving for game <id> - skipping
  ```

- [ ] **Resolution failure:** Turn resolution throws error
  ```
  # Simulate by corrupting state
  # Expected: [ERROR] Daemon: Turn resolution failed for game <id>: <error>
  # Expected: model.resolving flag cleared (game not stuck)
  ```

- [ ] **Mixed human/AI:** 2 human + 2 AI game
  ```
  # Assign pubkeys to houses 1-2 only
  # Submit commands from houses 1-2
  # Expected: Auto-resolves (doesn't wait for AI houses 3-4)
  ```

### ✅ Performance

- [ ] Query overhead negligible (<1ms per command submission)
- [ ] No database locks or contention
- [ ] Resolution completes in <1s for typical game

### ✅ Integration

- [ ] Works with manual CLI `./bin/ec4x-daemon resolve <game-id>`
- [ ] Works with Nostr transport (30402 events)
- [ ] Works with local file transport (if implemented)
- [ ] Delta publishing (30403) triggers after auto-resolve
- [ ] Full state publishing (30405) works on slot claim

---

## Troubleshooting

### Issue: Auto-resolve doesn't trigger

**Check:**
1. Game phase is "Active"
   ```bash
   sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT phase FROM games;"
   ```

2. Houses have pubkeys assigned
   ```bash
   sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT id, nostr_pubkey FROM houses WHERE nostr_pubkey IS NOT NULL;"
   ```

3. Commands are for current turn
   ```bash
   sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT turn FROM games;"
   sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT DISTINCT turn FROM commands WHERE processed = 0;"
   ```

4. All expected players submitted
   ```bash
   sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT COUNT(DISTINCT house_id) FROM commands WHERE turn = 1 AND processed = 0;"
   ```

### Issue: Turn doesn't advance

**Check daemon logs for errors:**
```bash
grep -i "error\|failed" daemon.log
```

**Verify resolution completed:**
```bash
sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT turn FROM games;"
sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT processed FROM commands WHERE turn = 1;"
# All should be 1 (processed)
```

### Issue: Players don't receive deltas

**Check Nostr publishing:**
```bash
grep "Publishing turn results" daemon.log
```

**Verify player pubkeys:**
```bash
sqlite3 "data/games/$GAME_ID/ec4x.db" "SELECT id, nostr_pubkey FROM houses;"
```

---

## Success Criteria

✅ **Automated tests:** All 15 tests pass
✅ **Manual E2E:** Turn advances automatically when both players submit
✅ **Logs show:** "All players submitted! Auto-triggering resolution"
✅ **Turn counter:** Increments from 1 → 2 → 3 as players submit
✅ **Edge cases:** Behave as documented (turn mismatch rejected, phase gating works, etc.)
✅ **Performance:** Sub-second resolution latency

---

## Next Steps

1. **CI Integration:** Add `nimble testDaemon` to CI pipeline
2. **Monitoring:** Add metrics for auto-resolve trigger rate
3. **Alerts:** Alert on repeated resolution failures
4. **Documentation:** Update player guide with auto-resolve behavior
5. **Timeout feature:** Implement turn deadline auto-resolve (future enhancement)
