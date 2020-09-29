
# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

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
export JOB_TIMEOUT=${JOB_TIMEOUT:-7200}
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export WORKLOAD_NODE=${WORKLOAD_NODE}
export UUID=$(uuidgen)
bold=$(tput bold)
normal=$(tput sgr0)

if [[ ${WORKLOAD_NODE} ]]; then
  PIN_SERVER=$(oc get node ${WORKLOAD_NODE} -o go-template --template='{{index .metadata.labels "kubernetes.io/hostname" }}')
  export PIN_SERVER
fi

log() {
  echo ${bold}$(date "+%d-%m-%YT%H:%m:%S") ${@}${normal}
}

deploy_operator() {
  log "Cloning benchmark-operator from ${OPERATOR_REPO}"
  rm -rf benchmark-operator
  git clone ${OPERATOR_REPO} --depth 1
  log "Deploying benchmark-operator"
  oc apply -f benchmark-operator/resources/namespace.yaml
  oc apply -f benchmark-operator/deploy
  oc apply -f benchmark-operator/resources/backpack_role.yaml
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
  log "Waiting for benchmark kube-burner-${1}-${UUID} to complete"
  until oc get benchmark -n my-ripsaw kube-burner-${1}-${UUID} -o jsonpath="{.status.state}" | grep -Eq  "Complete|Failed"; do
    sleep 1
  done
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
