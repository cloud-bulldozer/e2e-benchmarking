#!/usr/bin/bash -e
set -e

. common.sh
export NUMBER_OF_ROUTES=${NUMBER_OF_ROUTES:-100}
CLIENTS="1 40 200"
CLIENTS_MIX_ALL_ROUTES="1 20 80"

deploy_infra
client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | grep Running | awk '{print $1}')
tune_liveness_probe
mix_size=small
for termination in ${TERMINATIONS}; do
  for clients in ${CLIENTS}; do
    for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
      run_mb
    done
  done
  if [[ ${termination} ==  "mix" ]]; then
    for clients in ${CLIENTS_MIX_ALL_ROUTES}; do
      for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
        mix_size=large
        run_mb
      done
    done
  fi
done
enable_ingress_operator
cleanup_infra
if [[ -n ${ES_SERVER} ]]; then
  log "Generating results in compare.yaml"
  ../../utils/touchstone-compare/run_compare.sh mb ${BASELINE_UUID} ${UUID}
  log "Generating CSV results"
  ./csv_gen.py -f compare.yaml -u ${BASELINE_UUID} ${UUID} -p ${PREFIX} ${BASELINE_PREFIX} -l ${LATENCY_TOLERANCE} -t ${THROUGHPUT_TOLERANCE}
fi
