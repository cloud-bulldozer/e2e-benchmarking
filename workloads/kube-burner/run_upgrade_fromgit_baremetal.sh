#!/usr/bin/env bash
#set -e

export TOTAL_MCPS=${TOTAL_MCPS:- }
export MCP_NODE_COUNT=${MCP_NODE_COUNT:- }
export CREATE_MCPS=${CREATE_MCPS:-0}   # 1 to set, 0 to skip

. common.sh

baremetal_upgrade_auxiliary
exit 1


