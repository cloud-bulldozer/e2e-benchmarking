#!/usr/bin/env bash
set -e

export MCP_SIZE=1
export MCP_NODE_COUNT=10

. common.sh

machineConfig_pool
exit 1


