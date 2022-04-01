#!/usr/bin/env bash
set -x

source ./common.sh

CR=api-load-crd.yaml

log "###############################################"
log "api-load tests: ${TESTS}"
log "###############################################"

run_workload ${CR}

log "Finished workload ${0}"
