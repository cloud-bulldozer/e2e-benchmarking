#!/usr/bin/bash -e

set -e

export TEST_JOB_ITERATIONS=${JOB_ITERATIONS:-1000}
export WORKLOAD=cluster-density
export REMOTE_CONFIG=${REMOTE_CONFIG:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/workloads/cluster-density/cluster-density.yml}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/metrics-profiles/metrics-aggregated.yml}

. common.sh

deploy_operator
check_running_benchmarks
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
deploy_workload
wait_for_benchmark ${WORKLOAD}
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 echo -e "snappy server as backup enabled"
 source ../../utils/snappy-move-results/common.sh
 
 tar -zcvf pprof.tar.gz ./pprof-data
 
 export workload=kube-burner-clusterdensity

 export snappy_path="$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$workload/$folder_date_time/"
 generate_metadata > metadata.json  
 ../../utils/snappy-move-results/run_snappy.sh pprof.tar.gz $snappy_path
 ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
 store_on_elastic
fi


exit ${rc}
