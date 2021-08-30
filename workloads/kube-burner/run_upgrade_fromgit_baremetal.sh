#!/usr/bin/env bash
#set -e

. common.sh

export TOTAL_MCPS=${TOTAL_MCPS:- }   # will skip if CREATE_MCPS_BOOL is set to false!
export MCP_NODE_COUNT=${MCP_NODE_COUNT:- }   # will skip if CREATE_MCPS_BOOL is set to false!
export CREATE_MCPS_BOOL=true   # true or false

baremetal_upgrade_auxiliary
exit 1



