#!/usr/bin/env bash
set -e

export TOTAL_MCPS=
export MCP_NODE_COUNT=

. common.sh

baremetal_upgrade_auxiliary
exit 1


