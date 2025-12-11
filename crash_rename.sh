#!/usr/bin/env bash

FILE=$1
CONTAINER=${2:-"php"}
TIMEOUT=5  # Max seconds to wait for file change detection
REVERTED=false
TEMP_MARKER="/tmp/frankenphp_change_detected_$$"

# Revert function
revert_file() {
    if [[ $REVERTED == true ]]; then
        exit
    fi
    sed -i 's/>>DEAD<</>>BEEF<</g' "$FILE" 2>/dev/null
    echo "Reverted to BEEF" >&2
    rm -f "$TEMP_MARKER"
    REVERTED=true
    exit
}

# Wait for container to detect file change
wait_for_file_change_detection() {
    local file_basename=$(basename "$FILE")
    rm -f "$TEMP_MARKER"

    # Start log following in background
    docker compose logs -f --since 1s "$CONTAINER" 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "filesystem change detected.*${file_basename}"; then
            touch "$TEMP_MARKER"
            pkill -P $$ docker
            break
        fi
    done &
    local logs_pid=$!

    # Wait for either detection or timeout (check every 100ms)
    local checks=0
    local max_checks=$((TIMEOUT * 10))  # 10 checks per second

    while [[ $checks -lt $max_checks ]]; do
        if [[ -f "$TEMP_MARKER" ]]; then
            kill $logs_pid 2>/dev/null
            wait $logs_pid 2>/dev/null
            echo "✓ File change detected"
            return 0
        fi
        sleep 0.1
        ((checks++))
    done

    # Timeout - kill log following
    kill $logs_pid 2>/dev/null
    wait $logs_pid 2>/dev/null
    echo "⏱ Timeout waiting for detection"
    return 1
}

# Ensure we revert on exit
trap revert_file EXIT INT TERM

DETECTED=0
MISSED=0

if [[ -z "$FILE" ]]; then
    echo "ERROR: No file provided" >&2
    exit 1
elif [[ ! -f "$FILE" ]]; then
    echo "ERROR: File not found: $FILE" >&2
    exit 1
fi

echo "Starting file modification cycles..."

while true; do
    if [[ $MISSED -gt 6 ]]; then
        echo "WARNING: ${MISSED} missed detections Success rate: $((DETECTED * 100 / (DETECTED + MISSED)))%"
    fi

    echo "Modifying: BEEF -> DEAD"
    sed -i 's/>>BEEF<</>>DEAD<</g' "$FILE" 2>/dev/null

    if wait_for_file_change_detection; then
        ((DETECTED++))
    else
        ((MISSED++))
    fi

    sleep 0.3

    echo "Modifying: DEAD -> BEEF"
    sed -i 's/>>DEAD<</>>BEEF<</g' "$FILE" 2>/dev/null

    if wait_for_file_change_detection; then
        ((DETECTED++))
    else
        ((MISSED++))
    fi

    sleep 0.3
done
