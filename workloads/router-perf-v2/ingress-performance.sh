#!/usr/bin/bash -e
set -e

source ./common.sh

get_scenario
deploy_infra
tune_workload_node apply
client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | grep Running | awk '{print $1}')
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
oc rsync -n http-scale-client $(oc get pod -l app=http-scale-client -n http-scale-client | grep Running | awk '{print $1}'):/tmp/results.csv ./
tune_workload_node delete
cleanup_infra
if [[ -n ${ES_SERVER} ]]; then
  if [[ ${BASELINE_UUID} != "" ]]; then 
    log "Generating results in compare.yaml"
    ../../utils/touchstone-compare/run_compare.sh mb ${BASELINE_UUID} ${UUID} ${NUM_NODES}
    python3 -m venv ./venv
    source ./venv/bin/activate
    python3 -m pip install -r requirements.txt
    log "Generating CSV results"
    ./csv_gen.py -f compare_output_${NUM_NODES}.yaml -u ${BASELINE_UUID} ${UUID} -p ${BASELINE_PREFIX} ${PREFIX} -l ${LATENCY_TOLERANCE} -t ${THROUGHPUT_TOLERANCE}
  else
    log "Generating results in compare.yaml"
    ../../utils/touchstone-compare/run_compare.sh mb ${UUID} ${NUM_NODES}
    python3 -m venv ./venv
    source ./venv/bin/activate
    python3 -m pip install -r requirements.txt
    log "Generating CSV results"
    ./csv_gen.py -f compare_output_${NUM_NODES}.yaml -u ${UUID} -p ${PREFIX} -l ${LATENCY_TOLERANCE} -t ${THROUGHPUT_TOLERANCE}
  fi
  deactivate && rm -rf venv
fi

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 snappy_backup
fi
