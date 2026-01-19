# TUI Expert Mode Commands

This guide covers the expert command mode in the EC4X TUI. Activate expert
mode with `:` and type commands on the prompt.

## Fleet Command Syntax

Fleet commands follow this pattern:

```
:01 fleet <fleetId> to <systemId> [roe <0-10>]
:00 fleet <fleetId> [roe <0-10>]
```

You can use full names, aliases, or numeric codes from
`docs/specs/06-operations.md`.

## Fleet Command Codes

Each command has a two-digit code and a canonical name.

```
00 hold          01 move          02 seek
03 patrol        04 guard-starbase
05 guard         06 blockade      07 bombard
08 invade        09 blitz         10 colonize
11 scout-colony  12 scout-system  13 hack
14 join          15 rendezvous    16 salvage
17 reserve       18 mothball      19 view
```

### Fleet Command Patterns

```
:02 fleet <id>
:04 fleet <id> to <systemId>
:05 fleet <id> to <systemId>
:06 fleet <id> to <systemId>
:07 fleet <id> to <systemId>
:08 fleet <id> to <systemId>
:09 fleet <id> to <systemId>
:10 fleet <id> to <systemId>
:11 fleet <id> to <systemId>
:12 fleet <id> to <systemId>
:13 fleet <id> to <systemId>
:14 fleet <id> to <fleetId>
:15 fleet <id> to <systemId>
:16 fleet <id>
:17 fleet <id>
:18 fleet <id>
:19 fleet <id> to <systemId>
```

### Examples

```
:01 fleet 5 to 12 roe 6
:move fleet 5 to 12
:00 fleet 3
:hold fleet 3 roe 2
:02 fleet 4
:03 fleet 6 roe 4
:04 fleet 2 to 9
:05 fleet 7 to 11
:14 fleet 8 to 2
:join fleet 8 to 2
:07 fleet 9 to 11
:b colony 1 ship Destroyer quantity 2
```

## Build Commands

```
:build colony <id> ship <class> [quantity <n>]
:build colony <id> facility <type>
```

## Meta Commands

```
:help or :?        Show command summary
:list or :ls        Show staged commands
:drop <n> or :rm    Remove staged command by index
:clear              Clear all staged commands
:submit             Submit turn (bypass Ctrl+E confirmation)
```

## History Navigation

While in expert mode:

- Up arrow: previous command
- Down arrow: next command
- Command history resets when you submit a command

## Notes

- Use Ctrl+E twice to submit the current turn from normal mode.
- `:submit` bypasses confirmation and submits immediately.
- `:list` shows numbered commands. Use those numbers with `:drop`.
