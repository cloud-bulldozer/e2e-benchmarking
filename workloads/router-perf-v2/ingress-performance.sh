#!/usr/bin/bash -e
set -e

. common.sh

deploy_infra
tune_workload_node create
tune_liveness_probe
for clients in ${CLIENTS}; do
  for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
    run_mb
  done
done
enable_ingress_operator
tune_workload_node delete
cleanup_infra
if [[ -n ${ES_SERVER} ]]; then
  log "Generating results in compare.yaml"
  ../../utils/touchstone-compare/run_compare.sh mb ${BASELINE_UUID} ${UUID}
  log "Generating CSV results"
  ./csv_gen.py -f compare.yaml -u ${UUID} ${BASELINE_UUID} -p ${PREFIX} ${BASELINE_PREFIX} -l ${LATENCY_TOLERANCE} -t ${THROUGHPUT_TOLERANCE}
fi
