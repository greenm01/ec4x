# EC4X Daemon - Autonomous Turn Processing

This directory contains the automated turn processing daemon, implemented
with the SAM (State-Action-Model) pattern for predictable async state
management.

## Architecture

- SAM core: `src/daemon/sam_core.nim`
- Main loop: `src/daemon/daemon.nim`
- Nostr transport: `src/daemon/transport/nostr/`
- Persistence: `src/daemon/persistence/`
- Command parsing: `src/daemon/parser/kdl_commands.nim`

See `docs/architecture/daemon-sam.md` for the full SAM design and flow
examples.

## Running

```bash
./bin/ec4x-daemon start
./bin/ec4x-daemon resolve --gameId <id>
```

## Configuration

- Daemon config: `config/daemon.kdl`
- Nostr config: `config/nostr.kdl`

See `docs/guides/daemon-setup.md` for setup details.
