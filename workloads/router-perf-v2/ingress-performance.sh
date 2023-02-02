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

if [[ ! ${HYPERSHIFT} == false ]]; then
  tune_workload_node apply
  reschedule_monitoring_stack worker
fi

client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | awk '/Running/{print $1}')

if [[ ! -z "${INGRESS_OPERATOR_IMAGE}" ]] || [[ ! -z "${HAPROXY_IMAGE}" ]]; then
  configure_ingress_images
fi

tune_liveness_probe
if [[ ${METADATA_COLLECTION} == "true" ]]; then
  collect_metadata
fi

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

if [[ ! -z "${INGRESS_OPERATOR_IMAGE}" ]]; then
  enable_ingress_operator
fi

log "Copying mb test results locally (large file)"
until oc rsync -n http-scale-client ${client_pod}:/tmp/results.csv ./; do
  echo "Transfer disrupted, retrying in 10 seconds..."
  sleep 10
done

if [[ ${HYPERSHIFT} == false ]]; then
  tune_workload_node delete
  reschedule_monitoring_stack infra
fi

cleanup_infra

export WORKLOAD="router-perf"
run_benchmark_comparison

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup "csv json" "http-perf.yml" "router-perf-v2"
fi
