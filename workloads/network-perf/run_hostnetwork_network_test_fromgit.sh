#!/usr/bin/env bash
export WORKLOAD=hostnet

source ./common.sh
export pairs=1

deploy_workload
wait_for_benchmark
assign_uuid
run_benchmark_comparison
print_uuid
generate_csv

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 echo -e "snappy server as backup enabled"
 csv_list=`find . -name "*.csv"` 
 mkdir files_list
 cp $csv_list ./files_list
 tar -zcvf snappy_files.tar.gz ./files_list
 
 export workload=network_perf_hostnetwork_test
 export platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
 export cluster_version=$(oc get clusterversion | grep -o [0-9.]* | head -1)
 export network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
 export folder_date_time=$(TZ=UTC date +"%Y-%m-%d_%I:%M_%p")
 export SNAPPY_USER_FOLDER=${SNAPPY_USER_FOLDER:=perf-ci}

 if [[ -n $RUNID ]];then 
    runid=$RUNID-
 fi

 ../../utils/snappy-move-results/generate_metadata.sh > metadata.json 
 ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 ../../utils/snappy-move-results/run_snappy.sh metadata.json "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 rm -rf files_list
fi