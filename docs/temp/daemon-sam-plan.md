# EC4X Daemon: SAM Refactor + Basic Turn Progress Plan (v1.1)

## Goal
Daemon autonomous turn for localhost (KDL files) + nostr (NIP44 events).

## Status
- SAM ✅ (daemon/sam_core.nim async)
- Persistence stub ✅ (reader/writer)
- Localhost KDL ✅ (watcher/exporter)
- Cmds/reactors stub ✅
- Test game ID: 263dc85d-5a2e-4adf-8085-399841149102

## POC Test
1. `./bin/ec4x new --name test --scenario scenarios/standard-4-player.kdl`
2. mkdir houses/house_1; echo 'orders { }' > orders_pending.kdl
3. `nim r src/daemon/daemon.nim start --poll 1` → discover/collect/resolve stub logs.

## Phases Complete
- 0-3 ✅
- 4 Nostr stub
- 5 Docs/test pending

*(Full plan details...)*