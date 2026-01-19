# EC4X Game Management via Chat Bot

## Overview

This guide explains how to use a Discord/Telegram chat bot for remote game administration.
Sysops run the bot centrally; admins manage games via chat commands without server access.

## Sysop vs Admin Roles

### Sysop (System Operator)
- **Full Control**: Nostr relay, daemon, databases, bot hosting
- **Tools**: `bin/ec4x` CLI for game creation/infra
- **Responsibilities**:
  - Create games (`./bin/ec4x new`)
  - Run daemon/bot
  - Approve admin verifications
  - Monitor logs/revoke access

### Admin (Game Moderator)
- **Remote Access**: Chat commands only (no SSH/server login)
- **Tools**: Discord/Telegram client
- **Responsibilities**:
  - Generate/share invite codes
  - Start/stop/pause specific games
  - View roster/status
- **Privileges**: npub-verified, per-game permissions

## CLI Integration (ec4x invite Command)

The bot uses `ec4x invite` subprocess for code queries.

### Usage
```
ec4x invite --game-id &lt;uuid&gt; [--house &lt;name&gt;] [--full] [--reissue] [--export &lt;file&gt;]
```

Examples:
- `ec4x invite --game-id game-123` → Masked list
- `ec4x invite --game-id game-123 --house Alpha --full` → Raw code
- `ec4x invite --game-id game-123 --reissue --house Beta` → New code

Add to creation: `./bin/ec4x new ... --export-invites invites.txt`

## Bot Setup (Sysop Only)

### Prerequisites
- Discord/Telegram bot token (create at discord.com/developers or Telegram BotFather)
- EC4X binaries built (`nimble buildAll`)
- Private Discord/Telegram channel/group

### Quick Install (Nim Bot Example)
```bash
# Clone hypothetical bot repo (or implement below)
cd ~/dev/ec4x-bot
nimble install  # deps: discordnim or telebot
nim c bot.nim
BOT_TOKEN=your_token ./bot --ec4x-bin /home/mag/dev/ec4x/bin/ec4x
```

**Bot Pseudocode** (src/bot.nim – extend as needed):
```nim
# Verify Discord ID -> npub mapping
proc verifyAdmin(discordId: string, npub: string, gameId: string) =
  # Sysop reaction approval
  # Store in game_admins table

proc handleCommand(msg: Message) =
  let npub = getStoredNpub(msg.author.id)
  if hasPerm(npub, msg.gameId, msg.action):
    runEc4xSubprocess(msg.action, msg.gameId)
```

### Schema Extension (Per-Game DB)
Run once per game:
```sql
sqlite3 data/games/<game-id>/ec4x.db &lt;&lt;EOF
CREATE TABLE IF NOT EXISTS game_admins (
  discord_id TEXT,
  npub TEXT PRIMARY KEY,
  permissions TEXT,  -- &quot;invite,start,stop&quot;
  game_id TEXT,
  approved_by TEXT,
  approved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
```

## End-to-End Workflow

1. **Sysop Creation**:
   ```
   ./bin/ec4x new --name &quot;TestGame&quot; --export-invites invites.txt
   ```
   → DB + optional TXT export (raw codes)

2. **Sysop Bot Start**: `./ec4x-bot`

3. **Admin Verify**: `/request-admin game-123 npub1...` → Sysop approve

4. **Admin Ops**: `/invite game-123 beta` → Bot runs CLI → DM code

5. **Recovery**: CLI query if bot down

## Admin Verification Flow (npub + Sysop Approval)

1. **Admin**: `/request-admin game-123 npub1abcde...`
2. **Bot**: `@sysop: Approve npub1abcde for game-123? [✅/❌]`
3. **Sysop**: ✅ (reaction)
4. **Bot**: `@admin ✅ Verified! Use /help`

- **Revoke**: Sysop `/kick @admin game-123`
- **List**: `/admins game-123`

## Commands Reference

| Command | Permissions | Description | Example Output |
|---------|-------------|-------------|----------------|
| `/status &lt;game-id&gt;` | read | Game status/roster | `Turn 5, Active. Alpha: npub1...` |
| `/start &lt;game-id&gt;` | start | Start game daemon | `Daemon started for game-123` |
| `/stop &lt;game-id&gt;` | stop | Pause game | `Game-123 paused` |
| `/invite &lt;game-id&gt; &lt;house&gt;` | invite | Reissue code (DM) | `[DM] New: velvet-mountain` |
| `/roster &lt;game-id&gt;` | read | npubs per house | `House1: npub1... (claimed)` |
| `/help` | none | Command list | Table above |

**Examples**:
```
Admin: /status game-123
Bot: Turn 2/Active | Houses: 3/4 claimed | DB: data/games/game-123/ec4x.db

Admin: /invite game-123 beta
Bot: [DM to Admin] Beta invite: copper-sunrise (SHA256 verified)
```

## Security & Best Practices

- **npub-Only**: Proves identity; sysop approval gates actions
- **Per-Game**: Granular access (no cross-game leaks)
- **Auditing**: All commands logged to sysop channel
- **Rate Limits**: 5/min per admin/game
- **Private Channels**: Sysop controls membership
- **Invite Masking**: Codes masked in channel (`ve***-mou***`), full DM
- **Revocation**: Instant via /kick

## Troubleshooting

- **&quot;No perms&quot;**: Re-verify or sysop check DB
- **Bot Down**: Sysop restart + check logs
- **npub Changed**: /reverify

## Integration & Next Steps

- **Game Creation**: Unchanged (`./bin/ec4x new` → auto-add sysop as admin)
- **Player Flow**: TUI + Nostr unchanged
- **Extend Bot**: Add /resolve-turn, /kick-player

**References**:
- [Local Nostr Setup](local-nostr-development.md)
- [Nostr Protocol](architecture/nostr-protocol.md)
- [Daemon Docs](architecture/daemon.md)

**Last Updated**: 2026-01-19
