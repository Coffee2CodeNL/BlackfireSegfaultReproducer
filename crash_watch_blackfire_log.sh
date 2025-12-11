#!/usr/bin/env bash

BLACKFIRE_LOG_PATH="blackfire.log"
SEGFAULT_LOG=$1
CRASH_COUNT=0

if [[ -z "$SEGFAULT_LOG" ]]; then
    echo "ERROR: Missing argument. Usage: $0 <segfault_log_file>"
    exit 1
fi

# Check if log file exists
if [[ ! -f "$BLACKFIRE_LOG_PATH" ]]; then
    echo "WARNING: ${BLACKFIRE_LOG_PATH} not found, waiting for it to be created..."
    while [[ ! -f "$BLACKFIRE_LOG_PATH" ]]; do
        sleep 1
    done
    echo "Log file found, starting monitoring..."
fi

echo "Monitoring ${BLACKFIRE_LOG_PATH} for segfaults..."

# Get initial line count to avoid processing old crashes
INITIAL_LINES=$(wc -l < "$BLACKFIRE_LOG_PATH" 2>/dev/null || echo "0")

while true; do
    # Check if file still exists
    if [[ ! -f "$BLACKFIRE_LOG_PATH" ]]; then
        echo "WARNING: Log file disappeared, waiting..."
        sleep 1
        continue
    fi

    # Read new lines from the log
    CURRENT_LINES=$(wc -l < "$BLACKFIRE_LOG_PATH" 2>/dev/null || echo "$INITIAL_LINES")

    if [[ $CURRENT_LINES -gt $INITIAL_LINES ]]; then
        # Extract new lines
        NEW_LINES=$((CURRENT_LINES - INITIAL_LINES))
        NEW_CONTENT=$(tail -n "$NEW_LINES" "$BLACKFIRE_LOG_PATH" 2>/dev/null)

        # Check for segfault
        if echo "$NEW_CONTENT" | grep -q "SIGSEGV"; then
            ((CRASH_COUNT++))
            CRASH_TIME=$(date '+%Y-%m-%d %H:%M:%S')

            echo "🔥 SEGFAULT DETECTED! (#${CRASH_COUNT}) at ${CRASH_TIME}"

            # Extract the full crash report (from SIGSEGV until first blank line)
            CRASH_REPORT=$(echo "$NEW_CONTENT" | awk '/SIGSEGV/,/^$/ {print} /^$/ {if (found) exit; if (/SIGSEGV/) found=1}')

            # Save to segfault log
            {
                echo "==================== SEGFAULT #${CRASH_COUNT} - ${CRASH_TIME} ===================="
                echo "$CRASH_REPORT"
                echo ""
            } >> "$SEGFAULT_LOG"

            echo "📝 Crash details saved to ${SEGFAULT_LOG}"
            exit 1
        fi

        INITIAL_LINES=$CURRENT_LINES
    fi

    sleep 1
done
