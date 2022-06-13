#!/usr/bin/env bash
set -x

source ./common.sh

CR=api-load-crd.yaml

log "###############################################"
log "api-load tests: ${TESTS}"
log "###############################################"

prepare_tests
run_workload ${CR}
aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY || true

log "Finished workload ${0}"
