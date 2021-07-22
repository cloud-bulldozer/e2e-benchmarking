#!/usr/bin/env bash
set -xeEo pipefail

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
  if [[ ${COMPARE_WITH_GOLD} == "true" ]]; then 
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
 echo -e "snappy server as backup enabled"
 source ../../utils/snappy-move-results/common.sh
 csv_list=`find . -name "*.csv"` 
 json_list=`find . -name "*.json"`
 compare_file=`find . -name "compare*"`
 mkdir files_list
 cp $csv_list $compare_file $json_list http-perf.yml ./files_list
 tar -zcvf snappy_files.tar.gz ./files_list
 export workload=router-perf-v2
 
 export snappy_path="$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$UUID-$workload/$folder_date_time/"
 generate_metadata > metadata.json  
 ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz $snappy_path
 ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
 store_on_elastic
 rm -rf files_list
fi
