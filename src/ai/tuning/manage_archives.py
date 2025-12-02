#!/usr/bin/env python3
"""
Manage restic diagnostic archives.

Usage:
    python3 tools/ai_tuning/manage_archives.py list        # List all archives
    python3 tools/ai_tuning/manage_archives.py stats       # Show storage stats
    python3 tools/ai_tuning/manage_archives.py prune       # Clean old archives (keep last 10)
    python3 tools/ai_tuning/manage_archives.py restore <tag> [target_dir]  # Restore specific archive
"""

import subprocess
import sys
from pathlib import Path
from datetime import datetime

RESTIC_REPO = Path.home() / ".ec4x_test_data"
RESTIC_ENV = {
    "RESTIC_REPOSITORY": str(RESTIC_REPO),
    "RESTIC_PASSWORD": ""
}


def check_restic():
    """Check if restic is installed and repo exists."""
    try:
        subprocess.run(["restic", "version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: restic not installed")
        print("Install: https://restic.readthedocs.io/en/stable/020_installation.html")
        sys.exit(1)

    if not RESTIC_REPO.exists():
        print(f"No restic repository found at {RESTIC_REPO}")
        print("Archives are created automatically when you run diagnostics")
        sys.exit(0)


def list_archives():
    """List all diagnostic archives."""
    print(f"Diagnostic Archives in {RESTIC_REPO}")
    print("=" * 80)

    result = subprocess.run(
        ["restic", "snapshots", "--json"],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print("No archives found or repository not initialized")
        return

    import json
    snapshots = json.loads(result.stdout)

    if not snapshots:
        print("No archives found")
        return

    print(f"Found {len(snapshots)} archives:\n")
    print(f"{'Date':<20} {'Tag':<30} {'Files':<8} {'Size':<10}")
    print("-" * 80)

    for snap in snapshots:
        date = snap['time'][:19].replace('T', ' ')
        tags = ', '.join(snap.get('tags', []))

        # Get snapshot stats
        stats_result = subprocess.run(
            ["restic", "stats", snap['short_id'], "--json"],
            env=RESTIC_ENV,
            capture_output=True,
            text=True
        )

        if stats_result.returncode == 0:
            stats = json.loads(stats_result.stdout)
            size_mb = stats['total_size'] / 1024 / 1024
            files = stats['total_file_count']
            print(f"{date:<20} {tags:<30} {files:<8} {size_mb:>8.1f} MB")
        else:
            print(f"{date:<20} {tags:<30} {'?':<8} {'?':<10}")


def show_stats():
    """Show repository statistics."""
    print(f"Repository Statistics: {RESTIC_REPO}")
    print("=" * 80)

    # Overall stats
    result = subprocess.run(
        ["restic", "stats", "--mode", "raw-data"],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print("Could not retrieve statistics")
        return

    print(result.stdout)

    # Snapshot count
    snap_result = subprocess.run(
        ["restic", "snapshots", "--json"],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if snap_result.returncode == 0:
        import json
        snapshots = json.loads(snap_result.stdout)
        print(f"\nTotal archives: {len(snapshots)}")


def prune_archives(keep_last=10):
    """Prune old archives, keeping only the most recent N."""
    print(f"Pruning archives (keeping last {keep_last})...")
    print("=" * 80)

    result = subprocess.run(
        ["restic", "forget", "--keep-last", str(keep_last), "--prune"],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print(result.stdout)
        print(f"\n✓ Pruning complete - kept last {keep_last} archives")
    else:
        print(f"ERROR: {result.stderr}")
        sys.exit(1)


def restore_archive(tag, target_dir=None):
    """Restore a specific archive by tag."""
    if target_dir is None:
        target_dir = f"balance_results/restored_{tag}"

    target_path = Path(target_dir)
    target_path.mkdir(parents=True, exist_ok=True)

    print(f"Restoring archive with tag '{tag}' to {target_dir}")
    print("=" * 80)

    # Find snapshot by tag
    result = subprocess.run(
        ["restic", "snapshots", "--tag", tag, "--json"],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if result.returncode != 0 or not result.stdout.strip():
        print(f"ERROR: No archive found with tag '{tag}'")
        print("\nAvailable tags:")
        list_archives()
        sys.exit(1)

    import json
    snapshots = json.loads(result.stdout)

    if not snapshots:
        print(f"ERROR: No archive found with tag '{tag}'")
        sys.exit(1)

    snapshot_id = snapshots[0]['short_id']
    print(f"Found snapshot: {snapshot_id}")

    # Restore
    restore_result = subprocess.run(
        ["restic", "restore", snapshot_id, "--target", str(target_path)],
        env=RESTIC_ENV,
        capture_output=True,
        text=True
    )

    if restore_result.returncode == 0:
        print(f"\n✓ Archive restored to {target_dir}")
        print(f"\nFiles:")
        for csv_file in target_path.rglob("*.csv"):
            print(f"  - {csv_file}")
    else:
        print(f"ERROR: {restore_result.stderr}")
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    check_restic()

    command = sys.argv[1].lower()

    if command == "list":
        list_archives()
    elif command == "stats":
        show_stats()
    elif command == "prune":
        keep = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        prune_archives(keep)
    elif command == "restore":
        if len(sys.argv) < 3:
            print("ERROR: restore requires a tag")
            print("Usage: manage_archives.py restore <tag> [target_dir]")
            sys.exit(1)
        tag = sys.argv[2]
        target = sys.argv[3] if len(sys.argv) > 3 else None
        restore_archive(tag, target)
    else:
        print(f"ERROR: Unknown command '{command}'")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
