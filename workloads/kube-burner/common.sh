source env.sh

# If ES_SERVER is set and empty we disable ES indexing and metadata collection
if [[ -v ES_SERVER ]] && [[ -z ${ES_SERVER} ]]; then
  export METADATA_COLLECTION=false
else
  export PROM_TOKEN=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
fi
export NODE_SELECTOR_KEY="node-role.kubernetes.io/worker"
export NODE_SELECTOR_VALUE=""
export WAIT_WHEN_FINISHED=true
export WAIT_FOR=[]
export TOLERATIONS="[{key: role, value: workload, effect: NoSchedule}]"
export UUID=$(uuidgen)

# Check if we're on bareMetal
export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)

#Check to see if the infrastructure type is baremetal to adjust script as necessary 
if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
  log "BareMetal infastructure: setting isBareMetal accordingly"
  export isBareMetal=true
else
  export isBareMetal=false
fi


log() {
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

deploy_operator() {
  if [[ "${isBareMetal}" == "false" ]]; then
    log "Removing benchmark-operator namespace, if it already exists"
    oc delete namespace benchmark-operator --ignore-not-found
    log "Cloning benchmark-operator from branch ${OPERATOR_BRANCH} of ${OPERATOR_REPO}"
  else 
    log "Baremetal infrastructure: Keeping benchmark-operator namespace"
    log "Cloning benchmark-operator from branch ${OPERATOR_BRANCH} ${OPERATOR_REPO}"
  fi
    rm -rf benchmark-operator
    git clone --single-branch --branch ${OPERATOR_BRANCH} ${OPERATOR_REPO} --depth 1
    (cd benchmark-operator && make deploy)
    kubectl apply -f benchmark-operator/resources/backpack_role.yaml
    kubectl apply -f benchmark-operator/resources/kube-burner-role.yml
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
  until oc get pod -n benchmark-operator -l job-name=kube-burner-${suuid} --ignore-not-found -o jsonpath="{.items[*].status.phase}" | grep -q Running; do
    sleep 1
    if [[ $(date +%s) -gt ${timeout} ]]; then
      log "Timeout waiting for job to be running"
      exit 1
    fi
  done
  log "Benchmark in progress"
  until oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.state}" | grep -Eq "Complete|Failed"; do
    if [[ ${LOG_STREAMING} == "true" ]]; then
      oc logs -n benchmark-operator -f -l job-name=kube-burner-${suuid} --ignore-errors=true || true
      sleep 20
    fi
    sleep 1
  done
  log "Benchmark finished, waiting for benchmark/kube-burner-${1}-${UUID} object to be updated"
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
  export NODE_SELECTOR_KEY="node-density"
  export NODE_SELECTOR_VALUE="enabled"
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
  if [[ ${WORKLOAD_NODE} =~ 'node-role.kubernetes.io/worker' ]]; then
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
    log "Another kube-burner benchmark is running at the moment" && exit 1
    oc get benchmark -n benchmark-operator
  fi
}

machineConfig_pool() {
  # Retrieve MachineConfig Pools 
  machineConfigPoolList=$(oc get machineconfigpool --no-headers | grep -v  master | awk '{print $1 }')
  mcpCount=${#machineConfigPoolList[@]}
  log "${mcpCount} MachineConfig Pool(s) detected"
  
  # Vars and arrays to be used in calculating new MCP CPU allocation
  mcpCountVar=1
  numMCP=0
  numNode=0
  nodeList=()
  AllocationCalcAmounts=()

  # Calculate allocatable CPU per MCP
  while [ $mcpCountVar -le $mcpCount ]; do
    nodes=$('oc get nodes --no-headers --selector=node-role.kubernetes.io/'${machineConfigPoolList[${numMCP}]} | awk '{print $1 }')
    tempNodeList+=(${nodes[@]})
    nodeCount=${#tempNodeList[@]}
    allocationAmounts=()
    nodeCountVar=1
    while [ $nodeCountVar -le $nodeCount ]; do
      nodeAllocCPU=$(oc get ${tempNodeList[numNode]} -o json | jq .status.allocatable.cpu)
      nodeAllocCPUint=${nodeAllocCPU//[a-z]/}
      allocationAmounts+=($nodeAllocCPUint)
      ((nodeCountVar++))
      ((numNode++))
    done
    nodeCountVar=1
    sumAllocCPU=$(IFS=+; echo "$((${allocationAmounts[*]}))")
    fiftyPercentCalc=$(( sumAllocCPU / 2 ))
    newAllocatable="${fiftyPercentCalc}m"
    AllocationCalcAmounts+=($newAllocatable)
    calcReplica=$(( $fiftyPercentCalc / 1000 ))

    # Create new project
    newProject="${machineConfigPoolList[$numMCP]}-test"
    log "Creating new project ${newProject}"
    oc new-project $newProject

    # Export vars and deploy sample app
    export PROJECT=$newProject
    export REPLICA=$calcReplica
    export NODE_SELECTOR_KEY="node-role.kubernetes.io/"${machineConfigPoolList[${numMCP}]}
    export NODE_SELECTOR_VALUE=""
    log "Deploying $calcReplica replica(s) of the sample-app in MCP: ${machineConfigPoolList[${numMCP}]}"
    oc apply -f deployment-sampleapp.yml

    # Unset vars and begin to loop to next MCP
    nodeList+=(${tempNodeList[@]})
    unset tempNodeList
    unset PROJECT
    unset REPLICA
    unset NODE_SELECTOR_KEY
    unset NODE_SELECTOR_VALUE
    ((mcpCountVar++))
    ((numMCP++))
  done

cleanup() {
  oc delete ns -l kube-burner-uuid=${UUID}
}

