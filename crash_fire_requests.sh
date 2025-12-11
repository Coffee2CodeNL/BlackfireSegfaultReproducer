#!/usr/bin/env bash

COUNTER=0
SUCCESS_COUNT=0
FAIL_COUNT=0

while true; do
    EC=0
    curl https://localhost/ -kfs -m 1 -o /dev/null || EC=$?

    if [[ $EC -ne 0 ]]; then
        echo "ERROR! Starting retry with exponential backoff..."

        FAILURES=0
        MAX_RETRIES=20
        EXP_BACKOFF_BASE=1
        EXP_BACKOFF_MAX=4

        while true; do
            if (( FAILURES >= MAX_RETRIES )); then
                echo "CRITICAL: Container appears dead after ${MAX_RETRIES} retries!"
                exit 1
            fi

            TIMEOUT=$(( EXP_BACKOFF_BASE * 2 ** FAILURES ))
            if (( TIMEOUT > EXP_BACKOFF_MAX )); then
                TIMEOUT=$EXP_BACKOFF_MAX
            fi

            echo "Retry $((FAILURES + 1))/${MAX_RETRIES} with ${TIMEOUT}s timeout..."

            EC=0
            START=$(date +%s)
            curl https://localhost/ -kfs -m "$TIMEOUT" -o /dev/null || EC=$?
            END=$(date +%s)
            DIFF=$((END - START))
            if [[ "$TIMEOUT" -gt "$DIFF" ]]; then
                SLEEP=$((TIMEOUT - DIFF))
                echo "Request took ${DIFF}s instead of ${TIMEOUT}s, waiting ${SLEEP}s}..."
                sleep "$SLEEP"
            fi

            if [[ $EC -eq 0 ]]; then
                echo "Recovery successful after $((FAILURES + 1)) retries!"
                ((SUCCESS_COUNT++))
                break
            else
                REASON="Other (${EC})"
                if [[ "$EC" -eq 7 ]]; then
                    REASON="Could not connect to host"
                    echo "Request HARD FAILED (Reason: ${REASON}, Total Failures: ${FAIL_COUNT}), exiting..."
                    exit 1
                elif [[ "$EC" -eq 28 ]]; then
                    REASON="Operation timed out"
                elif [[ "$EC" -eq 35 ]]; then
                    REASON="SSL issue"
                    echo "Request HARD FAILED (Reason: ${REASON}, Total Failures: ${FAIL_COUNT}), exiting..."
                    exit 1
                fi
                echo "Request SOFT FAILED (Reason: ${REASON}, Total Failures: ${FAIL_COUNT})"
            fi

            ((FAILURES++))
            ((FAIL_COUNT++))
        done
    else
        ((SUCCESS_COUNT++))
        ((COUNTER++))
        if (( COUNTER % 20 == 0 )); then
            echo "20 requests succeeded (Total: Success=$SUCCESS_COUNT, Failed=$FAIL_COUNT)"
        fi
    fi

    sleep 0.5
done
