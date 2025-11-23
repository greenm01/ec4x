#!/usr/bin/env bash
# View and restore archived test data from restic

RESTIC_REPO="$HOME/.ec4x_test_data"
export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD=""

if [ ! -d "$RESTIC_REPO" ]; then
    echo "No test data archives found at $RESTIC_REPO"
    exit 1
fi

case "${1:-list}" in
    list)
        echo "Archived test data snapshots:"
        echo "=============================="
        restic snapshots
        ;;

    snapshots)
        restic snapshots
        ;;

    tags)
        echo "Available date tags:"
        echo "==================="
        restic tag --group-by tags list
        ;;

    restore)
        if [ -z "$2" ]; then
            echo "Usage: $0 restore <snapshot_id> [target_dir]"
            echo ""
            echo "Available snapshots:"
            restic snapshots
            exit 1
        fi

        TARGET="${3:-./restored_test_data}"
        echo "Restoring snapshot $2 to $TARGET..."
        restic restore "$2" --target "$TARGET"
        echo "✓ Restored to $TARGET"
        ;;

    restore-date)
        if [ -z "$2" ]; then
            echo "Usage: $0 restore-date <date_tag> [target_dir]"
            echo ""
            echo "Available tags:"
            restic tag --group-by tags list
            exit 1
        fi

        TARGET="${3:-./restored_test_data}"
        echo "Restoring data from $2 to $TARGET..."
        restic restore --tag "$2" latest --target "$TARGET"
        echo "✓ Restored to $TARGET"
        ;;

    prune)
        echo "Pruning old archives (keeping last 30 days)..."
        restic forget --keep-within 30d --prune
        echo "✓ Old archives pruned"
        ;;

    stats)
        echo "Repository statistics:"
        echo "====================="
        restic stats
        ;;

    help|*)
        cat <<EOF
EC4X Test Data Archive Manager (using restic)

Usage: $0 <command> [args]

Commands:
  list              List all archived snapshots (default)
  snapshots         Same as list
  tags              Show all date tags
  restore <id>      Restore a specific snapshot by ID
  restore-date <date> Restore by date tag (e.g., 2025-11-23_103045)
  prune             Remove archives older than 30 days
  stats             Show repository statistics
  help              Show this help

Examples:
  $0 list
  $0 restore 1a2b3c4d ./my_old_data
  $0 restore-date 2025-11-23_103045
  $0 prune

Archives are stored at: $RESTIC_REPO
Each test run automatically archives old results with a date tag.
EOF
        ;;
esac
