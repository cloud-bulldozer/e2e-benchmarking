export METADATA_COLLECTION=${METADATA_COLLECTION:-true}
export CERBERUS_URL=${CERBERUS_URL}
export QPS=${QPS:-10}
export BURST=${BURST:-10}
export ES_SERVER=${ES_SERVER:-https://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com}
export ES_PORT=${ES_PORT:-443}
export ES_INDEX=${ES_INDEX:-ripsaw-kube-burner}
export PROM_URL=${PROM_URL:-https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091}
OPERATOR_REPO=https://github.com/cloud-bulldozer/benchmark-operator.git
export NODE_SELECTOR_KEY="node-role.kubernetes.io/worker"
export NODE_SELECTOR_VALUE=""
PROM_TOKEN=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
export PROM_TOKEN
export WAIT_WHEN_FINISHED=true
export WAIT_FOR=[]
export JOB_TIMEOUT=${JOB_TIMEOUT:-14400}
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export WORKLOAD_NODE=${WORKLOAD_NODE}
export STEP_SIZE=${STEP_SIZE:-30s}
export METRICS_PROFILE=${METRICS_PROFILE:-metrics-aggregated.yaml}
export UUID=$(uuidgen)
export LOG_STREAMING=${LOG_STREAMING:-true}
export CLEANUP=${CLEANUP:-true}
export CLEANUP_WHEN_FINISH=${CLEANUP_WHEN_FINISH:-false}
export LOG_LEVEL=${LOG_LEVEL:-info}

bold=$(tput bold)
normal=$(tput sgr0)

if [[ ${WORKLOAD_NODE} ]]; then
  PIN_SERVER=$(oc get node ${WORKLOAD_NODE} -o go-template --template='{{index .metadata.labels "kubernetes.io/hostname" }}')
  export PIN_SERVER
fi

log() {
  echo ${bold}$(date "+%d-%m-%YT%H:%M:%S") ${@}${normal}
}

deploy_operator() {
  log "Cloning benchmark-operator from ${OPERATOR_REPO}"
  rm -rf benchmark-operator
  git clone ${OPERATOR_REPO} --depth 1
  log "Deploying benchmark-operator"
  oc apply -f benchmark-operator/resources/namespace.yaml
  oc apply -f benchmark-operator/deploy
  oc apply -f benchmark-operator/resources/kube-burner-role.yml
  oc apply -f benchmark-operator/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
  oc apply -f benchmark-operator/resources/operator.yaml
  log "Waiting for benchmark-operator to be available"
  oc wait --for=condition=available -n my-ripsaw deployment/benchmark-operator --timeout=180s
}

deploy_workload() {
  log "Deploying benchmark"
  envsubst < kube-burner-crd.yaml | oc apply -f -
}

wait_for_benchmark() {
  rc=0
  log "Waiting for kube-burner job to be created"
  until oc get benchmark -n my-ripsaw kube-burner-${1}-${UUID} -o jsonpath="{.status.state}" | grep -q Running; do
    sleep 1
  done
  log "Waiting for kube-burner job to start"
  suuid=$(oc get benchmark -n my-ripsaw kube-burner-${1}-${UUID} -o jsonpath="{.status.suuid}")
  until oc get pod -n my-ripsaw -l job-name=kube-burner-${suuid} --ignore-not-found -o jsonpath="{.items[*].status.phase}" | grep -q Running; do
    sleep 1
  done
  log "Benchmark in progress"
  until oc get benchmark -n my-ripsaw kube-burner-${1}-${UUID} -o jsonpath="{.status.state}" | grep -Eq "Complete|Failed"; do
    if [[ ${LOG_STREAMING} == "true" ]]; then
      oc logs -n my-ripsaw -f -l job-name=kube-burner-${suuid}
    fi
    sleep 1
  done
  log "Benchmark finished, waiting for benchmark/kube-burner-${1}-${UUID} object to be updated"
  if [[ ${LOG_STREAMING} == "false" ]]; then
    oc logs -n my-ripsaw --tail=-1 -l job-name=kube-burner-${suuid}
  fi
  oc get pod -l job-name=kube-burner-${suuid} -n my-ripsaw
  status=$(oc get benchmark -n my-ripsaw kube-burner-${1}-${UUID} -o jsonpath="{.status.state}")
  log "Benchmark kube-burner-${1}-${UUID} finished with status: ${status}"
  if [[ ${status} == "Failed" ]]; then
    rc=1
  fi
}

label_nodes() {
  export NODE_SELECTOR_KEY="kubelet-density"
  export NODE_SELECTOR_VALUE="enabled"
  if [[ ${NODE_COUNT} -le 0 ]]; then
    log "Node count <= 0: ${NODE_COUNT}"
    exit 1
  fi
  nodes=$(oc get node -o name -l node-role.kubernetes.io/worker= | head -${NODE_COUNT})
  if [[ $(echo "${nodes}" | wc -l) -lt ${NODE_COUNT} ]]; then
    log "Not enough worker nodes to label"
    exit 1
  fi
  for n in ${nodes}; do
    pods=$(oc describe ${n} | awk '/Non-terminated/{print $3}' | sed "s/(//g")
    pod_count=$((pods + pod_count))
  done
  total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count))
  log "Total running pods across nodes: ${pod_count}"
  if [[ ${total_pod_count} -le 0 ]]; then
    log "Number of pods to deploy <= 0"
    exit 1
  fi
  log "Number of pods to deploy on nodes: ${total_pod_count}"
  if [[ ${1} == "heavy" ]]; then
    total_pod_count=$((total_pod_count / 2))
  fi
  export JOB_ITERATIONS=${total_pod_count}
  log "Labeling ${NODE_COUNT} worker nodes with kubelet-density=enabled"
  for n in ${nodes}; do
    oc label ${n} kubelet-density=enabled --overwrite
  done
}

unlabel_nodes() {
  log "Removing kubelet-density=enabled label from worker nodes"
  for n in ${nodes}; do
    oc label ${n} kubelet-density-
  done
}

check_running_benchmarks() {
  benchmarks=$(oc get benchmark -n my-ripsaw --ignore-not-found | grep -vE "Failed|Complete" | wc -l)
  if [[ ${benchmarks} -gt 1 ]]; then
    log "Another kube-burner benchmark is running at the moment" && exit 1
  fi
}

cleanup() {
  oc delete ns -l kube-burner-uuid=${UUID}
}

