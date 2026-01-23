#!/bin/bash
# Shared perfscale library functions
# Source this file in scripts: source /usr/local/share/perfscale-lib.sh

# Git clone with retry for transient failures (e.g., GitHub 500 errors)
# Usage: retry_git_clone [git clone arguments...]
# Example: retry_git_clone https://github.com/org/repo --branch v1.0 --depth 1
retry_git_clone() {
    local max_attempts=5
    local delay=10
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if git clone "$@"; then
            return 0
        fi
        echo "git clone failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
        sleep $delay
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    echo "git clone failed after $max_attempts attempts"
    return 1
}

# Export functions so they're available in subshells
export -f retry_git_clone
