#!/bin/bash

set -euo pipefail

state=${1:-"start"}
state=$(echo "$state" | tr '[:upper:]' '[:lower:]')

# ----------------------------------------------------------
# Function to determine which docker compose command to use
# ----------------------------------------------------------
get_docker_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif docker-compose version &>/dev/null; then
        echo "docker-compose"
    else
        echo "ERROR: Neither 'docker compose' nor 'docker-compose' is installed or available in PATH." >&2
        exit 1
    fi
}

# Detect and assign the correct compose command
DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"
STACK_ENV="${SCRIPT_DIR}/stack.env"
if [ ! -f "$STACK_ENV" ]; then
    echo "Missing ${STACK_ENV}" >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$STACK_ENV"
set +a

# Match build.sh: only literal true (any case) enables an engine.
env_is_true() {
    [ "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" = "true" ]
}

compose_files="compose/docker-compose.yml"
if env_is_true "${ENABLE_TRINO:-}"; then
    compose_files="${compose_files}:compose/docker-compose.trino.yml"
fi
if env_is_true "${ENABLE_PRESTO:-}"; then
    compose_files="${compose_files}:compose/docker-compose.presto.yml"
fi
printf 'COMPOSE_FILE=%s\n' "$compose_files" >"${SCRIPT_DIR}/.env.compose"

set -a
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/.env.compose" ] && . "$SCRIPT_DIR/.env.compose"
set +a
export COMPOSE_FILE

case "$state" in
  start)
    $DOCKER_COMPOSE_CMD up -d
    ;;
  stop)
    $DOCKER_COMPOSE_CMD down
    ;;
  restart)
    $DOCKER_COMPOSE_CMD down
    $DOCKER_COMPOSE_CMD up -d --build
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac
