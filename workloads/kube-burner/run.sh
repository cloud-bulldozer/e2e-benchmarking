#!/usr/bin/bash
# shellcheck disable=SC2155

. common.sh
. build_helper.sh

deploy_operator
check_running_benchmarks

case ${WORKLOAD} in
  cluster-density)
    WORKLOAD_TEMPLATE=workloads/cluster-density/cluster-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${JOB_ITERATIONS:-1000}
  ;;
  node-density)
    WORKLOAD_TEMPLATE=workloads/node-pod-density/node-pod-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    PODS_PER_NODE=${PODS_PER_NODE:-245}
    find_running_pods_num regular
  ;;
  node-density-heavy)
    WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    PODS_PER_NODE=${PODS_PER_NODE:-245}
    find_running_pods_num heavy
  ;;
  node-density-cni)
    WORKLOAD_TEMPLATE=workloads/node-density-cni/node-density-cni.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    PODS_PER_NODE=${PODS_PER_NODE:-245}
    find_running_pods_num cni
  ;;
  node-density-cni-networkpolicy)
    WORKLOAD_TEMPLATE=workloads/node-density-cni-networkpolicy/node-density-cni-networkpolicy.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    PODS_PER_NODE=${PODS_PER_NODE:-245}
    find_running_pods_num cni
  ;;
  pod-density)
    WORKLOAD_TEMPLATE=workloads/node-pod-density/node-pod-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    export TEST_JOB_ITERATIONS=${PODS:-1000}
  ;;
  pod-density-heavy)
    WORKLOAD_TEMPLATE=workloads/node-density-heavy/node-density-heavy.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics.yaml}
    export TEST_JOB_ITERATIONS=${PODS:-1000}
  ;;
  max-namespaces)
    WORKLOAD_TEMPLATE=workloads/max-namespaces/max-namespaces.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${NAMESPACE_COUNT:-1000}
  ;;
  max-services)
    WORKLOAD_TEMPLATE=workloads/max-services/max-services.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export TEST_JOB_ITERATIONS=${SERVICE_COUNT:-1000}
  ;;
  concurrent-builds)
    rm -rf conc_builds_results.out
    WORKLOAD_TEMPLATE=workloads/concurrent-builds/concurrent-builds.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/metrics-aggregated.yaml}
    export build_test_repo=${BUILD_TEST_REPO:=https://github.com/openshift/svt.git}
    export build_test_branch=${BUILD_TEST_BRANCH:=master}
    install_svt_repo
    export build_array=("${BUILD_LIST}")
    max=1
    for v in "${build_array[@]}" ; do
        if (( $v > $max )); then
          max=$v
        fi
    done
    export MAX_CONC_BUILDS=$((max + 1))
    export TEST_JOB_ITERATIONS=${MAX_CONC_BUILDS:-$max}
  ;;
  cluster-density-ms)
    WORKLOAD_TEMPLATE=workloads/managed-services/cluster-density.yml
    METRICS_PROFILE=${METRICS_PROFILE:-metrics-profiles/hypershift-metrics.yaml}
    export TEST_JOB_ITERATIONS=${JOB_ITERATIONS:-75}
  ;;
  custom)
  ;;
  *)
     log "Unknown workload ${WORKLOAD}, exiting"
     exit 1
  ;;
esac

cat << EOF
###############################################
Workload: ${WORKLOAD}
Workload template: ${WORKLOAD_TEMPLATE}
Metrics profile: ${METRICS_PROFILE}
Alerts profile: ${ALERTS_PROFILE}
QPS: ${QPS}
Burst: ${BURST}
UUID: ${UUID}
EOF
if [[ ${WORKLOAD} == node-density* ]]; then
  echo "Pods per node: ${PODS_PER_NODE}"
else
  echo "Job iterations: ${TEST_JOB_ITERATIONS}"
fi
echo "###############################################"
if [[ ${PPROF_COLLECTION} == "true" ]] ; then
  delete_pprof_secrets
  delete_oldpprof_folder
  get_pprof_secrets
fi

if [[ ${WORKLOAD} == "concurrent-builds" ]]; then
   app_array=("${APP_LIST}")
   for app in "${app_array[@]}"
    do
      run_build_workload $app
  done
  cat conc_builds_results.out
else
  run_workload kube-burner-crd.yaml
fi

if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  cleanup
fi
delete_pprof_secrets
if [[ ${ENABLE_SNAPPY_BACKUP} == "true" ]] ; then
  tar czf pprof.tar.gz ./pprof-data
  snappy_backup "" "pprof.tar.gz" ${WORKLOAD}
fi
run_benchmark_comparison

if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
  remove_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
else
  remove_cli
fi

exit "${rc}"
