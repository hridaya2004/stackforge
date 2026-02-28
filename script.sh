#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_stacks() {
    find "$SCRIPT_DIR" -mindepth 2 -maxdepth 2 -name 'docker-compose.yaml' -printf '%h\n' | sort
}

is_running() {
    docker compose -f "$1/docker-compose.yaml" ps -q 2>/dev/null | grep -q .
}

# Strip @sha256:... from image lines so docker compose pull works
unpin_digests() {
    sed -i -E 's|(image:[[:space:]]+)([^@]+)@sha256:[a-f0-9]+|\1\2|' "$1"
}

# Replace each image reference with its pinned sha256 digest
pin_digests() {
    local file="$1"
    local tmpfile
    tmpfile="$(mktemp)"

    while IFS= read -r line; do
        if [[ "$line" =~ ^([[:space:]]*image:[[:space:]]*)(.+)$ ]]; then
            local prefix="${BASH_REMATCH[1]}"
            local name="${BASH_REMATCH[2]}"
            # Get the repo digest (e.g. registry/image@sha256:abc123)
            local pinned
            pinned="$(docker inspect --format='{{index .RepoDigests 0}}' "$name" 2>/dev/null || true)"
            if [ -n "$pinned" ]; then
                echo "${prefix}${pinned}"
            else
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "$file" > "$tmpfile"

    mv "$tmpfile" "$file"
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

    # Unpin digests so docker compose pull resolves :latest
    for dir in $(get_stacks); do
        unpin_digests "$dir/docker-compose.yaml"
    done

    echo "Pulling latest images..."
    local pids=()
    for dir in $(get_stacks); do
        docker compose -f "$dir/docker-compose.yaml" pull &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Pin images to their pulled sha256 digests
    echo "Pinning digests..."
    for dir in $(get_stacks); do
        pin_digests "$dir/docker-compose.yaml"
    done

    if [ ${#running_stacks[@]} -gt 0 ]; then
        echo "Restarting stacks..."
        for dir in "${running_stacks[@]}"; do
            docker compose -f "$dir/docker-compose.yaml" up -d
        done
    fi

    echo "Update complete."
}

do_pin() {
    # Unpin digests so docker compose pull resolves :latest
    for dir in $(get_stacks); do
        unpin_digests "$dir/docker-compose.yaml"
    done

    echo "Pulling latest images..."
    local pids=()
    for dir in $(get_stacks); do
        docker compose -f "$dir/docker-compose.yaml" pull &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    echo "Pinning digests..."
    for dir in $(get_stacks); do
        pin_digests "$dir/docker-compose.yaml"
    done
    echo "Done."
}

usage() {
    echo "Usage: $(basename "$0") {update|pin|run|stop}"
    echo
    echo "  update  - Pull latest images, pin digests, restart running containers"
    echo "  pin     - Pull latest images and pin digests without restarting"
    echo "  run     - Start all stacks"
    echo "  stop    - Stop all stacks"
    exit 1
}

case "${1:-}" in
    update) do_update ;;
    pin)    do_pin ;;
    run)    do_run ;;
    stop)   do_stop ;;
    *)      usage ;;
esac
