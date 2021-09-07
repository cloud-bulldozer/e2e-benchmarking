#!/usr/bin/env bash

source env.sh

# If INDEXING is disabled we disable metadata collection
if [[ ${INDEXING} == "false" ]]; then
  export METADATA_COLLECTION=false
  unset PROM_URL
else
  export PROM_TOKEN=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
fi
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export UUID=$(uuidgen)

log() {
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

collect_pprof() {
  sleep 50
  while [ $(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.complete}") == "false" ]; do
    log "-----------------------checking for new pprof files--------------------------"
    oc rsync -n benchmark-operator $(oc get pod -n benchmark-operator | grep "kube-burner" | grep Running | awk '{print $1}'):/tmp/pprof-data $PWD/
    sleep 60
  done
}


deploy_operator() {
  log "Removing benchmark-operator namespace, if it already exists"
  oc delete namespace benchmark-operator --ignore-not-found
  log "Cloning benchmark-operator from branch ${OPERATOR_BRANCH} of ${OPERATOR_REPO}"
  rm -rf benchmark-operator
  git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
  (cd benchmark-operator && make deploy)
  kubectl apply -f benchmark-operator/resources/backpack_role.yaml
  kubectl apply -f benchmark-operator/resources/kube-burner-role.yml
  log "Waiting for benchmark-operator to be running"
  oc wait --for=condition=available "deployment/benchmark-controller-manager" -n benchmark-operator --timeout=300s
}

deploy_workload() {
  log "Deploying benchmark"
  envsubst < kube-burner-crd.yaml | oc apply -f -
}

wait_for_benchmark() {
  rc=0
  log "Waiting for kube-burner job to be created"
  local timeout=$(date -d "+${POD_READY_TIMEOUT} seconds" +%s)
  until oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.state}" | grep -q Running; do
    sleep 1
    if [[ $(date +%s) -gt ${timeout} ]]; then
      log "Timeout waiting for job to be created"
      exit 1
    fi
  done
  log "Waiting for kube-burner job to start"
  suuid=$(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.suuid}")
  until oc get pod -n benchmark-operator -l job-name=kube-burner-${suuid} --ignore-not-found -o jsonpath="{.items[*].status.phase}" | grep -Eq "Running|Failed"; do
    sleep 1
    if [[ $(date +%s) -gt ${timeout} ]]; then
      log "Timeout waiting for job to be running"
      oc logs -n benchmark-operator --tail=-1 -l job-name=kube-burner-${suuid} --ignore-errors=true
      cleanup
      exit 1
    fi
  done
  log "Benchmark in progress"
  if [[ ${PPROF_COLLECTION} == "true" ]] ; then
    collect_pprof ${1} &
    pid=$!
    log "PID ${pid} for pprof collection is running in the background"
  fi

  until [[ $(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.complete}") == "true" ]]; do
    if [[ ${LOG_STREAMING} == "true" ]]; then
      oc logs -n benchmark-operator --tail=-1 -f -l job-name=kube-burner-${suuid} --ignore-errors=true || true
      sleep 20
    fi
    sleep 1
  done
  log "Benchmark kube-burner-${1}-${UUID} finished"
  if [[ ${LOG_STREAMING} == "false" ]]; then
    oc logs -n benchmark-operator --tail=-1 -l job-name=kube-burner-${suuid}
  fi
  oc get pod -l job-name=kube-burner-${suuid} -n benchmark-operator
  status=$(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.state}")
  log "Benchmark kube-burner-${1}-${UUID} finished with status: ${status}"
  if [[ ${status} == "Failed" ]]; then
    rc=1
  fi
  oc get benchmark -n benchmark-operator
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
export certkey=`oc get secret -n openshift-etcd | grep "etcd-serving-ip" | head -1 | awk '{print $1}'`
echo `oc extract -n openshift-etcd secret/$certkey`
export CERTIFICATE=`base64 -w0 tls.crt`
export KEY=`base64 -w0 tls.key`
export BEARER_TOKEN=$(oc sa get-token kube-burner -n benchmark-operator)
}

delete_pprof_secrets() {
rm -f tls.key tls.crt
}

delete_oldpprof_folder() {
rm -rf pprof-data
}

