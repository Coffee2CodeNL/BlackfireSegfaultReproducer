#!/usr/bin/env bash

CONTAINER=$1
COUNTER=0

if [[ -z "$CONTAINER" ]]; then
    echo "ERROR: No container name provided"
    exit 1
fi

echo "Monitoring container '${CONTAINER}' health..."

while true; do
    CONTAINER_INFO=$(docker compose ps --format json "$CONTAINER" 2>/dev/null)
    STATUS=$(echo "$CONTAINER_INFO" | jq -r '.State')
    HEALTH=$(echo "$CONTAINER_INFO" | jq -r '.Health')

    # Check for crashed state
    if [[ "$STATUS" != "running" || "$HEALTH" != "healthy"  ]]; then
        echo "CRITICAL: Crash detected! State: $STATUS, Health: $HEALTH"
        exit 1
    fi

    ((COUNTER++))
    if (( COUNTER % 15 == 0 )); then
        echo "Heartbeat: State=$STATUS, Health=$HEALTH, Checks=$COUNTER"
    fi

    sleep 0.5
done
