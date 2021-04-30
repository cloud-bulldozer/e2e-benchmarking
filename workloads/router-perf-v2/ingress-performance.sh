#!/usr/bin/bash -e
set -e

. common.sh

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
tune_workload_node delete
cleanup_infra
if [[ -n ${ES_SERVER} ]]; then
  log "Generating results in compare.yaml"
  ../../utils/touchstone-compare/run_compare.sh mb ${BASELINE_UUID} ${UUID} ${NUM_NODES}
  log "Generating CSV results"
  ./csv_gen.py -f compare_output_${NUM_NODES}.yaml -u ${BASELINE_UUID} ${UUID} -p ${BASELINE_PREFIX} ${PREFIX} -l ${LATENCY_TOLERANCE} -t ${THROUGHPUT_TOLERANCE}
fi

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 echo -e "snappy server as backup enabled"
 csv_list=`find . -name "*.csv"` 
 mkdir files_list
 cp $csv_list compare.yaml http-scale-mix.json http-scale-http.json http-perf.yml ./files_list
 tar -zcvf snappy_files.tar.gz ./files_list
 export workload=router-perf-v2
 export platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
 export cluster_version=$(oc get clusterversion | grep -o [0-9.]* | head -1)
 export network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
 export folder_date_time=$(date +"%Y-%m-%d_%I:%M_%p")

 if [[ -n $RUNID ]];then 
    runid=$RUNID-
 fi

 ../../utils/snappy-move-results/generate_metadata.sh > metadata.json 
 ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 ../../utils/snappy-move-results/run_snappy.sh metadata.json "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 rm -rf files_list
fi
