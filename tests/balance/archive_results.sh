#!/bin/bash
## Archive Balance Test Results
##
## Moves test results to timestamped archive with metadata
## Usage: ./archive_results.sh [--label LABEL] [--source DIR]

set -e

# Configuration
BALANCE_RESULTS="/home/niltempus/dev/ec4x/balance_results"
ARCHIVE_DIR="$BALANCE_RESULTS/archive"
SOURCE_DIR="$BALANCE_RESULTS/coevolution"
LABEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --label)
            LABEL="$2"
            shift 2
            ;;
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--label LABEL] [--source DIR]"
            exit 1
            ;;
    esac
done

# Generate timestamp
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
if [ -n "$LABEL" ]; then
    ARCHIVE_NAME="${TIMESTAMP}_${LABEL}"
else
    ARCHIVE_NAME="$TIMESTAMP"
fi

DEST_DIR="$ARCHIVE_DIR/$ARCHIVE_NAME"

echo "======================================================================="
echo "Archiving Balance Test Results"
echo "======================================================================="
echo "Source:      $SOURCE_DIR"
echo "Destination: $DEST_DIR"
echo ""

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Check if source has any results (JSON or logs)
HAS_JSON=$(ls $SOURCE_DIR/*.json 2>/dev/null | wc -l)
HAS_LOGS=$(find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.json.log" \) 2>/dev/null | wc -l)
HAS_REPORT=$([ -f "$SOURCE_DIR/ANALYSIS_REPORT.md" ] && echo "1" || echo "0")

if [ "$HAS_JSON" -eq 0 ] && [ "$HAS_LOGS" -eq 0 ] && [ "$HAS_REPORT" -eq 0 ]; then
    echo "Warning: No test results found in source directory"
    echo "Skipping archival"
    exit 0
fi

# Create archive directory
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$DEST_DIR"

# Capture metadata
echo "Capturing metadata..."
cat > "$DEST_DIR/metadata.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "source_dir": "$SOURCE_DIR",
  "archive_name": "$ARCHIVE_NAME",
  "git_hash": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
  "git_branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
  "git_dirty": $([ -n "$(git status --porcelain 2>/dev/null)" ] && echo "true" || echo "false"),
  "test_type": "$(basename $SOURCE_DIR)",
  "result_files": [
$(ls $SOURCE_DIR/*.json 2>/dev/null | sed 's/.*/"&"/' | paste -sd, || echo '""')
  ]
}
EOF

# Move JSON files (keep uncompressed for easy access)
echo "Moving result files..."
mv $SOURCE_DIR/*.json "$DEST_DIR/" 2>/dev/null || true

# Move analysis report
if [ -f "$SOURCE_DIR/ANALYSIS_REPORT.md" ]; then
    mv "$SOURCE_DIR/ANALYSIS_REPORT.md" "$DEST_DIR/"
fi

# Compress log files (they're huge - can be 1GB+ each)
echo "Compressing log files..."
LOG_FILES=$(find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.json.log" \) 2>/dev/null)
if [ -n "$LOG_FILES" ]; then
    echo "  Found $(echo "$LOG_FILES" | wc -l) log files"
    # Use tar with files from stdin to handle large filenames and spaces
    find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.json.log" \) -printf "%P\n" | \
        tar -czf "$DEST_DIR/logs.tar.gz" -C "$SOURCE_DIR" -T -

    # Remove original log files
    find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.json.log" \) -delete

    LOG_SIZE=$(du -h "$DEST_DIR/logs.tar.gz" | cut -f1)
    echo "  Compressed logs: $LOG_SIZE"
else
    echo "  No log files to compress"
fi

# Generate summary
TOTAL_FILES=$(ls -1 "$DEST_DIR" | wc -l)
TOTAL_SIZE=$(du -sh "$DEST_DIR" | cut -f1)

echo ""
echo "✅ Archival complete!"
echo ""
echo "Archived: $TOTAL_FILES files ($TOTAL_SIZE)"
echo "Location: $DEST_DIR"
echo ""

# Update archive index
ARCHIVE_INDEX="$ARCHIVE_DIR/index.json"
if [ ! -f "$ARCHIVE_INDEX" ]; then
    echo "[]" > "$ARCHIVE_INDEX"
fi

# Add entry to index (using jq if available, otherwise append)
if command -v jq &> /dev/null; then
    TEMP_INDEX=$(mktemp)
    jq ". += [{
        \"name\": \"$ARCHIVE_NAME\",
        \"timestamp\": \"$(date -Iseconds)\",
        \"path\": \"$DEST_DIR\",
        \"git_hash\": \"$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')\",
        \"size\": \"$TOTAL_SIZE\"
    }]" "$ARCHIVE_INDEX" > "$TEMP_INDEX"
    mv "$TEMP_INDEX" "$ARCHIVE_INDEX"
else
    echo "Note: jq not installed, skipping index update"
fi

echo "View results: cat $DEST_DIR/ANALYSIS_REPORT.md"
echo "======================================================================="
