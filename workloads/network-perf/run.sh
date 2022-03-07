#!/usr/bin/env bash

source ./common.sh

CR=ripsaw-uperf-crd.yaml

case ${WORKLOAD} in
  pod2pod)
  ;;
  pod2svc)
    export SERVICEIP=true
  ;;
  hostnet)
    export HOSTNETWORK=true
  ;;
  smoke)
    COMPARISON_CONFIG=uperf-touchstone-smoke.json
    CR=smoke-crd.yaml
    export SAMPLES=1
  ;;
  *)
     log "Unkonwn workload ${WORKLOAD}, exiting"
     exit 1
  ;;
esac

log "###############################################"
log "Workload: ${WORKLOAD}"
log "Network policy: ${NETWORK_POLICY}"
log "Samples: ${SAMPLES}"
log "Pairs: ${PAIRS}"
if [[ ${SERVICEIP} == "true" && ${SERVICETYPE} == "metallb" ]]; then
  log "Service type: ${SERVICETYPE}"
  log "Address pool: ${ADDRESSPOOL}"
  log "Service ETP: ${SERVICE_ET}"
fi
log "###############################################"

count=0
for pairs in ${PAIRS}; do
  export PAIRS=${pairs}
  if [ $count -gt 0 ]; then
    export METADATA_COLLECTION=false
  fi
  if ! run_workload ${CR}; then
    exit 1
  fi
  ((count++))
done

BASELINE_UUID=${BASELINE_POD_UUID}
COMPARISON_OUTPUT=${PWD}/${WORKLOAD}-${UUID}.csv
run_benchmark_comparison

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  snappy_backup network_perf_${WORKLOAD}_test
fi
log "Finished workload ${0}"
