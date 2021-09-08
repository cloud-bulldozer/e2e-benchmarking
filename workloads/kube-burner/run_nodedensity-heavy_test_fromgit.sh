#!/usr/bin/bash -e

set -e

NODE_COUNT=${NODE_COUNT:-4}
PODS_PER_NODE=${PODS_PER_NODE:-250}
export WORKLOAD=node-density-heavy
export REMOTE_CONFIG=${REMOTE_CONFIG:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/workloads/node-density-heavy/node-density-heavy.yml}
export REMOTE_METRIC_PROFILE=${REMOTE_METRIC_PROFILE:-https://raw.githubusercontent.com/cloud-bulldozer/e2e-benchmarking/master/workloads/kube-burner/metrics-profiles/metrics.yml}

. common.sh

deploy_operator
check_running_benchmarks
label_nodes heavy
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi 
deploy_workload
wait_for_benchmark ${WORKLOAD}
unlabel_nodes
rm -rf benchmark-operator
if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets

if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
 echo -e "snappy server as backup enabled"
 source ../../utils/snappy-move-results/common.sh
 
 tar -zcvf pprof.tar.gz ./pprof-data
 
 export workload=kube-burner-nodedensityheavy

 export snappy_path="$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$workload/$folder_date_time/"
 generate_metadata > metadata.json  
 ../../utils/snappy-move-results/run_snappy.sh pprof.tar.gz $snappy_path
 ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
 store_on_elastic
fi


exit ${rc}
