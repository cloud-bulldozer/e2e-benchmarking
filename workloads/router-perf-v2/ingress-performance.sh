#!/usr/bin/bash -e
set -e

source ./common.sh
source ../../utils/compare.sh

get_scenario
log "###############################################"
log "Routes: ${NUMBER_OF_ROUTES}"
log "Routers: ${NUMBER_OF_ROUTERS}"
log "Service type: ${SERVICE_TYPE}"
log "Terminations: ${TERMINATIONS}"
log "Deployment replicas: ${DEPLOYMENT_REPLICAS}"
log "###############################################"
check_hypershift
deploy_infra
tune_workload_node apply
client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | awk '/Running/{print $1}')
if [[ ${RESCHEDULE_MONITORING_STACK} == "true" ]]; then
  reschedule_monitoring_stack worker
fi
configure_ingress_images
tune_liveness_probe
if [[ ${METADATA_COLLECTION} == "true" ]]; then
  collect_metadata
fi

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
test_routes
for termination in ${TERMINATIONS}; do
  if [[ ${termination} ==  "mix" ]]; then
    for clients in ${CLIENTS_MIX}; do
      for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
        run_mb
      done
    done
  else
    for clients in ${CLIENTS}; do
      for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
        run_mb
      done
    done
  fi
done
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

enable_ingress_operator
log "Copying mb test results locally (large file)"
until oc rsync -n http-scale-client ${client_pod}:/tmp/results.csv ./; do
  echo "Transfer disrupted, retrying in 10 seconds..."
  sleep 10
done

tune_workload_node delete
cleanup_infra
if [[ ${RESCHEDULE_MONITORING_STACK} == "true" ]]; then
  reschedule_monitoring_stack infra
fi

export WORKLOAD="router-perf"

# Do not exit when compare function has any non 0 return code when COMPARISON_RC=1
set +e
if ! run_benchmark_comparison; then
  log "Benchmark comparison failed"
  JOB_STATUS="failed"
else
  JOB_STATUS="success"
fi
set -e

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup "csv json" "http-perf.yml" "router-perf-v2"
fi

env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" ../../utils/index.sh
if [[ ${JOB_STATUS} == "failed" ]] ; then
 exit 1
fi
