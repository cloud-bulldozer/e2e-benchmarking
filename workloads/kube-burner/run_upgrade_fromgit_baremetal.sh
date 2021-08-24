#!/usr/bin/env bash
set -e

export MCP_SIZE=
export MCP_NODE_COUNT=

. common.sh

baremetal_upgrade_auxiliary
exit 1


