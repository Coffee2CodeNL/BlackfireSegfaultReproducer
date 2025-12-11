#!/usr/bin/env bash

# --- Configuration ---
CONTAINER_NAME="php"
DOCKER_TIMEOUT=60
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="docker_container_${TIMESTAMP}.log"
BUILD_LOG_FILE="docker_build_${TIMESTAMP}.log"
SEGFAULT_LOG_FILE="segfaults_${TIMESTAMP}.log"
STOPPED=false

# --- Colors for Pretty Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# --- Cleanup Trap ---
cleanup() {
    if [[ "$STOPPED" == true ]]; then
        exit
    fi
    echo -e "\n${RED}[Manager] Stopping all scripts and waiting 5 seconds...${NC}"
    pkill -TERM -P $$
    sleep 5
    echo -e "${GREEN}[Manager] Docker logs saved to: ${LOG_FILE}${NC}"
    echo -e "${GREEN}[Manager] Build logs saved to: ${BUILD_LOG_FILE}${NC}"
    echo -e "${GREEN}[Manager] Segfault logs saved to: ${SEGFAULT_LOG_FILE}${NC}"
    STOPPED=true
    exit
}
trap cleanup EXIT INT TERM

# --- Verify Controller Target ---
echo -e "${BLUE}[Manager] Finding the Controller...${NC}"
CONTROLLER_PATH=$(find . -name "TestController.php" -print -quit | xargs realpath)
echo -e "${GREEN}[Manager] Found Controller: ${CONTROLLER_PATH}${NC}"
echo -e "${BLUE}[Manager] Verifying that Controller has the proper replacer target...${NC}"
grep -q '>>BEEF<<' "$CONTROLLER_PATH" || CONTROLLER_TARGET=$?
if [[ "$CONTROLLER_TARGET" -ne 0 ]]; then
    echo -e "${RED}[Manager] Controller does not have the proper replacer target!${NC}"
else
    REP_TARGET_LINE=$(grep -n '>>BEEF<<' "$CONTROLLER_PATH" | cut -d: -f1)
    echo -e "${GREEN}[Manager] Controller has the proper replacer target on line ${REP_TARGET_LINE}!${NC}"
fi

if [[ ! -f "blackfire.log" ]]; then
    touch blackfire.log
fi

# --- Check Docker Stack Status ---
echo -e "${BLUE}[Manager] Checking docker stack status...${NC}"
STACK_STATUS=$(docker compose ps | wc -l)
if [[ "$STACK_STATUS" -gt 1 ]]; then
    echo -e "${RED}[Manager] Docker stack is already running! Shutting down${NC}"
    docker compose down &> /dev/null
else
    echo -e "${GREEN}[Manager] Docker stack is not running.${NC}"
fi

# --- Start Environment ---
echo -e "${BLUE}[Manager] Building Docker Environment...${NC}"
echo -e "${BLUE}[Manager] Build log: ${BUILD_LOG_FILE} (run 'tail -f ${BUILD_LOG_FILE}' to follow)${NC}"
if [[ $1 == "--no-cache" ]]; then
    echo -e "${YELLOW}[Manager] --no-cache flag detected. Building without cache...${NC}"
    docker compose --progress plain build --pull --no-cache &> "$BUILD_LOG_FILE"
else
    docker compose --progress plain build --pull &> "$BUILD_LOG_FILE"
fi
if [[ $? -ne 0 ]]; then
    echo -e "${RED}[Manager] Docker build failed! Check ${BUILD_LOG_FILE}${NC}"
    exit 1
fi

echo -e "${BLUE}[Manager] Starting Docker Environment...${NC}"
docker compose --progress plain up -d &> "$BUILD_LOG_FILE"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}[Manager] Docker start failed! Check ${BUILD_LOG_FILE}${NC}"
    exit 1
fi

echo -e "${BLUE}[Manager] Waiting for container '${CONTAINER_NAME}' to be ready...${NC}"
wait_counter=$DOCKER_TIMEOUT
while [[ $(docker compose ps --format json "$CONTAINER_NAME" | jq -r '.State') != 'running' && $(docker compose ps --format json "$CONTAINER_NAME" | jq -r '.Health') != 'healthy' ]]; do
    if [[ $wait_counter -eq 0 ]]; then
        echo -e "${RED}[Manager] Timeout waiting for Docker!${NC}"
        exit 1
    fi
    echo -ne "\r${BLUE}[Manager]${NC} Waiting: ${wait_counter}s left..."
    ((wait_counter--))
    sleep 1
done
echo -e "${GREEN}[Manager] Docker is UP!${NC}"

settle_counter=10
while true; do
    if [[ "$settle_counter" -le 0 ]]; then
        break;
    fi

    echo -e "${BLUE}[Manager] Allowing FrankenPHP to settle, ${settle_counter}s left...${NC}"
    ((settle_counter--))
    sleep 1
done
echo -e "${GREEN}[Manager] FrankenPHP is settled! Starting segfault test...${NC}"


# --- Output debug information ---
echo -e "${BLUE}[Manager] PHP Version${NC}\n$(docker compose exec -T $CONTAINER_NAME php -v)"
echo -e "${BLUE}[Manager] PHP Modules${NC}\n$(docker compose exec -T $CONTAINER_NAME php -m)"
echo -e "${BLUE}[Manager] FrankenPHP Build Info${NC}\n$(docker compose exec -T $CONTAINER_NAME frankenphp build-info)}${NC}"

# --- Start Docker Logs Capture ---
echo -e "${BLUE}[Manager] Capturing Docker logs to ${LOG_FILE}...${NC}"
docker compose logs -f --no-color --since 0s "$CONTAINER_NAME" &> "$LOG_FILE" &

# --- Initialize Segfault Log ---
echo "Blackfire SIGSEGV Log - Started at $(date)" > "$SEGFAULT_LOG_FILE"
echo "==========================================" >> "$SEGFAULT_LOG_FILE"
echo "" >> "$SEGFAULT_LOG_FILE"

# --- Launch Parallel Scripts with Logging Prefixes ---
bash crash_fire_requests.sh 2>&1 | while IFS= read -r line; do echo -e "${CYAN}[Requester]${NC} ${line}"; done &
PID_REQ=$!

bash crash_rename.sh "$CONTROLLER_PATH" 2>&1 | while IFS= read -r line; do echo -e "${YELLOW}[Renamer]${NC} ${line}"; done &
PID_RENAME=$!

bash crash_watch_docker_status.sh "$CONTAINER_NAME" 2>&1 | while IFS= read -r line; do echo -e "${BLUE}[Monitor]${NC} ${line}"; done &
PID_MONITOR=$!

bash crash_watch_blackfire_log.sh "$SEGFAULT_LOG_FILE" 2>&1 | while IFS= read -r line; do echo -e "${MAGENTA}[Blackfire]${NC} ${line}"; done &
PID_BLACKFIRE=$!

# --- Wait for Crash ---
wait -n $PID_MONITOR $PID_REQ $PID_BLACKFIRE

echo -e "${RED}[Manager] CRASH DETECTED! Exiting test in 5 seconds.${NC}"
