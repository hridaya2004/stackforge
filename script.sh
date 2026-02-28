#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_stacks() {
    find "$SCRIPT_DIR" -mindepth 2 -maxdepth 2 -name 'docker-compose.yaml' -printf '%h\n' | sort
}

is_running() {
    docker compose -f "$1/docker-compose.yaml" ps -q 2>/dev/null | grep -q .
}

do_stop() {
    echo "Stopping stacks..."
    for dir in $(get_stacks); do
        is_running "$dir" && docker compose -f "$dir/docker-compose.yaml" down
    done
    echo "Done."
}

do_run() {
    echo "Starting stacks..."
    for dir in $(get_stacks); do
        is_running "$dir" || docker compose -f "$dir/docker-compose.yaml" up -d
    done
    echo "Done."
}

do_update() {
    local running_stacks=()
    for dir in $(get_stacks); do
        is_running "$dir" && running_stacks+=("$dir")
    done

    if [ ${#running_stacks[@]} -gt 0 ]; then
        echo "Stopping running stacks..."
        for dir in "${running_stacks[@]}"; do
            docker compose -f "$dir/docker-compose.yaml" down
        done
    fi

    echo "Pulling latest images..."
    local pids=()
    for dir in $(get_stacks); do
        docker compose -f "$dir/docker-compose.yaml" pull &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    if [ ${#running_stacks[@]} -gt 0 ]; then
        echo "Restarting stacks..."
        for dir in "${running_stacks[@]}"; do
            docker compose -f "$dir/docker-compose.yaml" up -d
        done
    fi

    echo "Update complete."
}

usage() {
    echo "Usage: $(basename "$0") {update|run|stop}"
    echo
    echo "  update  - Pull latest images, restart running containers"
    echo "  run     - Start all stacks"
    echo "  stop    - Stop all stacks"
    exit 1
}

case "${1:-}" in
    update) do_update ;;
    run)    do_run ;;
    stop)   do_stop ;;
    *)      usage ;;
esac
