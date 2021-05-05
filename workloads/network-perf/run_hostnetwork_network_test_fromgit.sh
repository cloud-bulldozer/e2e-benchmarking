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
 ../../utils/snappy-move-results/common.sh
 csv_list=`find . -name "*.csv"` 
 mkdir files_list
 cp $csv_list ./files_list
 tar -zcvf snappy_files.tar.gz ./files_list
 
 export workload=network_perf_hostnetwork_test

 ../../utils/snappy-move-results/generate_metadata.sh > metadata.json 
 ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 ../../utils/snappy-move-results/run_snappy.sh metadata.json "$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$uuid-$workload/$folder_date_time/"
 rm -rf files_list
fi