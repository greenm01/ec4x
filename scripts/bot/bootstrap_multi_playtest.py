#!/usr/bin/env python3
"""Bootstrap a full multi-bot playtest run with one command."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def run(cmd: list[str], cwd: Path, ok_codes: tuple[int, ...] = (0,)) -> str:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode not in ok_codes:
        msg = (
            f"Command failed: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )
        raise RuntimeError(msg)
    return proc.stdout


def parse_slug(new_output: str) -> str:
    match = re.search(r"Slug:\s*([a-z0-9-]+)", new_output)
    if not match:
        raise RuntimeError("Could not parse game slug from `ec4x new` output")
    return match.group(1)


def parse_invite_codes(invite_output: str) -> list[str]:
    codes: list[str] = []
    for line in invite_output.splitlines():
        match = re.search(r":\s*([a-z0-9-]+)@", line)
        if match:
            codes.append(match.group(1))
    return codes


def parse_keypairs(keys_output: str, bot_count: int) -> list[tuple[str, str]]:
    keypairs: list[tuple[str, str]] = []
    for line in keys_output.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        keypairs.append((parts[0], parts[1]))
    if len(keypairs) < bot_count:
        raise RuntimeError("Insufficient keypairs generated")
    return keypairs[:bot_count]


def decode_daemon_pubhex(identity_file: Path) -> str:
    text = identity_file.read_text()
    match = re.search(r'npub="(npub[0-9a-z]+)"', text)
    if not match:
        raise RuntimeError("Could not find daemon npub in daemon_identity.kdl")

    npub = match.group(1)
    charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    cmap = {c: i for i, c in enumerate(charset)}

    def polymod(values: list[int]) -> int:
        generator = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
        chk = 1
        for value in values:
            top = chk >> 25
            chk = ((chk & 0x1FFFFFF) << 5) ^ value
            for idx, poly in enumerate(generator):
                if (top >> idx) & 1:
                    chk ^= poly
        return chk

    def hrp_expand(hrp: str) -> list[int]:
        return [ord(ch) >> 5 for ch in hrp] + [0] + [ord(ch) & 31 for ch in hrp]

    def convert_bits(data: list[int], from_bits: int, to_bits: int) -> bytes:
        acc = 0
        bits = 0
        out: list[int] = []
        maxv = (1 << to_bits) - 1
        for value in data:
            if value < 0 or (value >> from_bits):
                raise RuntimeError("Invalid npub payload")
            acc = (acc << from_bits) | value
            bits += from_bits
            while bits >= to_bits:
                bits -= to_bits
                out.append((acc >> bits) & maxv)
        if bits >= from_bits or ((acc << (to_bits - bits)) & maxv):
            raise RuntimeError("Invalid npub bit conversion")
        return bytes(out)

    npub = npub.lower()
    pos = npub.rfind("1")
    if pos < 1 or pos + 7 > len(npub):
        raise RuntimeError("Malformed daemon npub")
    hrp = npub[:pos]
    data = [cmap[c] for c in npub[pos + 1 :]]
    if polymod(hrp_expand(hrp) + data) != 1:
        raise RuntimeError("Invalid daemon npub checksum")

    raw = convert_bits(data[:-6], 5, 8)
    return raw.hex()


def write_multi_env(
    env_file: Path,
    game_id: str,
    relay: str,
    daemon_pubhex: str,
    model: str,
    bot_count: int,
    keypairs: list[tuple[str, str]],
) -> None:
    lines = [
        f'BOT_RELAYS="{relay}"',
        f'BOT_GAME_ID="{game_id}"',
        f'BOT_DAEMON_PUBHEX="{daemon_pubhex}"',
        "",
        "# Shared LLM/provider settings",
        'BOT_BASE_URL="https://api.openai.com/v1"',
        'BOT_API_KEY="${BOT_API_KEY:-}"',
        f'BOT_MODEL_DEFAULT="{model}"',
        "",
        "# Runtime tuning",
        "BOT_MAX_RETRIES=2",
        "BOT_REQUEST_TIMEOUT_SEC=45",
        'BOT_LOG_ROOT="logs/bot/multi"',
        "",
        "# Optional process orchestration",
        "BOT_START_RELAY=0",
        "BOT_START_DAEMON=0",
        "",
        "# Optional reproducibility metadata",
        "BOT_SEED=\"\"",
        "BOT_CONFIG_HASH=\"\"",
        "",
        f"BOT_COUNT={bot_count}",
    ]

    for i in range(bot_count):
        priv_hex, pub_hex = keypairs[i]
        slot = i + 1
        lines.extend(
            [
                "",
                f"# Bot {slot} identity/model",
                f'BOT_{slot}_PLAYER_PRIV_HEX="{priv_hex}"',
                f'BOT_{slot}_PLAYER_PUB_HEX="{pub_hex}"',
                f'BOT_{slot}_MODEL="{model}"',
            ]
        )

    env_file.parent.mkdir(parents=True, exist_ok=True)
    env_file.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Clean, create game, claim invites, and launch multi-bot run"
    )
    parser.add_argument("--relay", default="ws://localhost:8080")
    parser.add_argument("--scenario", default="scenarios/standard-4-player.kdl")
    parser.add_argument("--bots", type=int, default=2)
    parser.add_argument(
        "--reserve",
        type=int,
        default=1,
        help="Number of invite slots to leave unclaimed for human players (default 1)",
    )
    parser.add_argument("--model", default="gpt-4o-mini")
    parser.add_argument(
        "--env-file",
        default="scripts/bot/multi_session.env",
        help="Output env file for multi-bot runner",
    )
    parser.add_argument(
        "--api-key-env",
        default="BOT_API_KEY",
        help="Environment variable that stores API key",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Skip the clean-dev step (useful when reusing an existing game)",
    )
    parser.add_argument(
        "--run-seconds",
        type=int,
        default=0,
        help="If >0, run multi-bot for N seconds",
    )
    parser.add_argument(
        "--run-gates",
        action="store_true",
        help="Run acceptance gate script after playtest run",
    )
    args = parser.parse_args()

    if args.bots < 1:
        raise RuntimeError("--bots must be >= 1")
    if args.reserve < 0:
        raise RuntimeError("--reserve must be >= 0")

    repo = Path(__file__).resolve().parents[2]
    ec4x_bin = repo / "bin" / "ec4x"
    if not ec4x_bin.exists():
        raise RuntimeError("Missing bin/ec4x. Build moderator first.")

    api_key = os.getenv(args.api_key_env, "")
    if not api_key:
        fallback = os.getenv("OPENAI_API_KEY", "")
        if fallback:
            api_key = fallback
        else:
            raise RuntimeError(
                f"Missing API key in ${args.api_key_env} (or OPENAI_API_KEY)"
            )

    if args.no_clean:
        print("[bootstrap] skipping clean (--no-clean)")
    else:
        print("[bootstrap] cleaning dev data")
        run(["nim", "r", "tools/clean_dev.nim", "--clean", "--logs"], repo)

    print("[bootstrap] creating game")
    new_output = run(
        ["bin/ec4x", "new", f"--scenario={args.scenario}"],
        repo,
    )
    game_slug = parse_slug(new_output)

    invite_output = run(["bin/ec4x", "invite", game_slug], repo)
    invite_codes = parse_invite_codes(invite_output)
    total_needed = args.bots + args.reserve
    if len(invite_codes) < total_needed:
        raise RuntimeError(
            f"Scenario only has {len(invite_codes)} invite codes but "
            f"--bots {args.bots} + --reserve {args.reserve} = {total_needed} required"
        )

    print(f"[bootstrap] game slug: {game_slug}")
    print("[bootstrap] generating bot keys")
    keys_output = run(
        ["nim", "r", "tools/gen_bot_keys.nim", str(args.bots)],
        repo,
    )
    keypairs = parse_keypairs(keys_output, args.bots)

    print("[bootstrap] claiming invites")
    for i in range(args.bots):
        priv_hex, pub_hex = keypairs[i]
        code = invite_codes[i]
        run(
            [
                "nim",
                "r",
                "tools/claim_invite.nim",
                args.relay,
                code,
                priv_hex,
                pub_hex,
            ],
            repo,
        )
        print(f"  bot{i+1} claimed {code}")

    human_codes = invite_codes[args.bots : args.bots + args.reserve]
    if human_codes:
        print("[bootstrap] unclaimed invite codes for human players:")
        for idx, code in enumerate(human_codes, start=1):
            line = f"  player{idx}: {code}@{args.relay}"
            print(line)
        human_invites_file = repo / "scripts" / "bot" / "human_invites.txt"
        human_invites_file.write_text(
            "\n".join(
                f"player{idx}: {code}@{args.relay}"
                for idx, code in enumerate(human_codes, start=1)
            )
            + "\n"
        )
        print(f"[bootstrap] invite codes saved to: {human_invites_file}")

    daemon_identity = Path.home() / ".local/share/ec4x/daemon_identity.kdl"
    daemon_pubhex = decode_daemon_pubhex(daemon_identity)

    env_file = repo / args.env_file
    write_multi_env(
        env_file=env_file,
        game_id=game_slug,
        relay=args.relay,
        daemon_pubhex=daemon_pubhex,
        model=args.model,
        bot_count=args.bots,
        keypairs=keypairs,
    )
    print(f"[bootstrap] wrote env file: {env_file}")

    if args.run_seconds > 0:
        print(f"[bootstrap] running multi-bot for {args.run_seconds}s")
        run(
            ["timeout", str(args.run_seconds), "scripts/run_multi_bot_playtest.sh"],
            repo,
            ok_codes=(0, 124),
        )

    if args.run_gates:
        print("[bootstrap] running acceptance gates")
        run(
            [
                "scripts/bot/run_acceptance_gates.sh",
                "logs/bot",
                "scripts/bot/scenario_matrix.example.json",
            ],
            repo,
        )

    print("[bootstrap] complete")
    print(f"[bootstrap] game: {game_slug}")
    if human_codes:
        print("[bootstrap] join the game with one of the invite codes above")
        print("[bootstrap] then run: scripts/run_multi_bot_playtest.sh")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"[bootstrap] error: {exc}", file=sys.stderr)
        raise SystemExit(1)
