#!/usr/bin/bash -e
set -e

source ./common.sh

get_scenario
log "###############################################"
log "Routes: ${NUMBER_OF_ROUTES}"
log "Routers: ${NUMBER_OF_ROUTERS}"
log "Service type: ${SERVICE_TYPE}"
log "Terminations: ${TERMINATIONS}"
log "Deployment replicas: ${DEPLOYMENT_REPLICAS}"
log "###############################################"
deploy_infra
tune_workload_node apply
client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | awk '/Running/{print $1}')
reschedule_monitoring_stack worker
configure_ingress_images
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

enable_ingress_operator
log "Copying mb test results locally (large file)"
until oc rsync -n http-scale-client ${client_pod}:/tmp/results.csv ./; do
  echo "Transfer disrupted, retrying in 10 seconds..."
  sleep 10
done

tune_workload_node delete
cleanup_infra
reschedule_monitoring_stack infra

if [[ -n ${ES_SERVER} ]]; then
  log "Installing touchstone"
  install_touchstone
  if [[ -n ${ES_SERVER_BASELINE} ]] && [[ -n ${BASELINE_UUID} ]]; then
    log "Comparing with baseline"
    compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" ${COMPARISON_CONFIG} ${COMPARISON_FORMAT}
  else
    log "Querying results"
    compare ${ES_SERVER} ${UUID} ${COMPARISON_CONFIG} ${COMPARISON_FORMAT}
  fi
  if [[ -n ${GSHEET_KEY_LOCATION} ]] && [[ ${COMPARISON_FORMAT} == "csv" ]]; then
    gen_spreadsheet ingress-performance ${COMPARISON_OUTPUT} ${EMAIL_ID_FOR_RESULTS_SHEET} ${GSHEET_KEY_LOCATION}
  fi
  log "Removing touchstone"
  remove_touchstone
fi

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup
fi
