#!/usr/bin/env bash

source ../../utils/benchmark-operator.sh
source env.sh

# If INDEXING is disabled we disable metadata collection
if [[ ${INDEXING} == "false" ]]; then
  export METADATA_COLLECTION=false
  unset PROM_URL
else
  export PROM_TOKEN=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
fi
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export UUID=${UUID:-$(uuidgen)}

log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

collect_pprof() {
  sleep 50
  while [ $(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.complete}") == "false" ]; do
    log "-----------------------checking for new pprof files--------------------------"
    oc rsync -n benchmark-operator $(oc get pod -n benchmark-operator -o name -l benchmark-uuid=${UUID}):/tmp/pprof-data $PWD/
    sleep 60
  done
}


deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
  if [[ $? != 0 ]]; then
    exit 1
  fi
  rm -rf benchmark-operator
  git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  kubectl apply -f benchmark-operator/resources/kube-burner-role.yml
}

run_workload() {
  set -e
  local tmpdir=$(mktemp -d)
  if [[ -z ${WORKLOAD_TEMPLATE} ]]; then
    log "WORKLOAD_TEMPLATE not defined or null!"
    exit 1
  fi
  cp -pR $(dirname ${WORKLOAD_TEMPLATE})/* ${tmpdir}
  envsubst < ${WORKLOAD_TEMPLATE} > ${tmpdir}/config.yml
  if [[ -n ${METRICS_PROFILE} ]]; then
    cp metrics-profiles/${METRICS_PROFILE} ${tmpdir}/metrics.yml || cp ${METRICS_PROFILE} ${tmpdir}/metrics.yml
  fi
  if [[ -n ${ALERTS_PROFILE} ]]; then
   cp ${ALERTS_PROFILE} ${tmpdir}/alerts.yml
  fi
  log "Creating kube-burner configmap"
  kubectl create configmap -n benchmark-operator --from-file=${tmpdir} kube-burner-cfg-${UUID}
  rm -rf ${tmpdir}
  log "Deploying benchmark"
  set +e
  local TMPCR=$(mktemp)
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} $((JOB_TIMEOUT + 600))
  local rc=$?
  if [[ ${TEST_CLEANUP} == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f ${TMPCR}
  fi
  return ${rc}
}

label_nodes() {
  export POD_NODE_SELECTOR="{node-density: enabled}"
  if [[ ${NODE_COUNT} -le 0 ]]; then
    log "Node count <= 0: ${NODE_COUNT}"
    exit 1
  fi
  nodes=$(oc get node -o name --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker= | head -${NODE_COUNT})
  if [[ $(echo "${nodes}" | wc -l) -lt ${NODE_COUNT} ]]; then
    log "Not enough worker nodes to label"
    exit 1
  fi
  pod_count=0
  for n in ${nodes}; do
    pods=$(oc describe ${n} | awk '/Non-terminated/{print $3}' | sed "s/(//g")
    pod_count=$((pods + pod_count))
  done
  log "Total running pods across nodes: ${pod_count}"
  if [[ ${NODE_SELECTOR} =~ node-role.kubernetes.io/worker ]]; then
    # Number of pods to deploy per node * number of labeled nodes - pods running - kube-burner pod
    log "kube-burner will run on a worker node, decreasing by one the number of pods to deploy"
    total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count - 1))
  else
    # Number of pods to deploy per node * number of labeled nodes - pods running
    total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count))
  fi
  if [[ ${total_pod_count} -le 0 ]]; then
    log "Number of pods to deploy <= 0"
    exit 1
  fi
  log "Number of pods to deploy on nodes: ${total_pod_count}"
  if [[ ${1} == "heavy" ]]; then
    total_pod_count=$((total_pod_count / 2))
  fi
  export TEST_JOB_ITERATIONS=${total_pod_count}
  log "Labeling ${NODE_COUNT} worker nodes with node-density=enabled"
  for n in ${nodes}; do
    oc label ${n} node-density=enabled --overwrite
  done
}

unlabel_nodes() {
  log "Removing node-density=enabled label from worker nodes"
  for n in ${nodes}; do
    oc label ${n} node-density-
  done
}

check_running_benchmarks() {
  benchmarks=$(oc get benchmark -n benchmark-operator | awk '{ if ($2 == "kube-burner")print}'| grep -vE "Failed|Complete" | wc -l)
  if [[ ${benchmarks} -gt 1 ]]; then
    log "Another kube-burner benchmark is running at the moment"
    oc get benchmark -n benchmark-operator
    exit 1
  fi
}

cleanup() {
  oc delete ns -l kube-burner-uuid=${UUID}
}

get_pprof_secrets() {
 local certkey=`oc get secret -n openshift-etcd | grep "etcd-serving-ip" | head -1 | awk '{print $1}'`
 oc extract -n openshift-etcd secret/$certkey
 export CERTIFICATE=`base64 -w0 tls.crt`
 export PRIVATE_KEY=`base64 -w0 tls.key`
 export BEARER_TOKEN=$(oc sa get-token kube-burner -n benchmark-operator)
}

delete_pprof_secrets() {
 rm -f tls.key tls.crt
}

delete_oldpprof_folder() {
 rm -rf pprof-data
}

snappy_backup() {
 log "snappy server as backup enabled"
 source ../../utils/snappy-move-results/common.sh
 tar -zcvf pprof.tar.gz ./pprof-data
 workload=${1}
 snappy_path="$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$workload/$folder_date_time/"
 generate_metadata > metadata.json  
 ../../utils/snappy-move-results/run_snappy.sh pprof.tar.gz $snappy_path
 ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
 store_on_elastic
}
