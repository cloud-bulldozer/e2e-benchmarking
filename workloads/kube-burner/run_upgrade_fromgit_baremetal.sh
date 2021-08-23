#!/usr/bin/env bash
set -e

export MCP_SIZE=1
export MCP_NODE_COUNT=10

. common.sh

baremetal_upgrade_auxiliary
exit 1


