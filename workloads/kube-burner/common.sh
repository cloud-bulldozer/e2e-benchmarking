source env.sh

log() {
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

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
  if [[ ${#NODE_COUNT} -eq 0 ]]; then
    log "Node count = 0: exiting"
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
total_mcps=$MCP_SIZE
mcp_node_count=$MCP_NODE_COUNT
# Calculate how many MCP's to use
log "Retrieving all nodes in the cluster that do not have the role 'master' or 'worker-lb'"
node_list=($(oc get nodes --no-headers | grep -v master | grep -v worker-lb | awk '{print $1}'))
node_count=${#node_list[@]}
if [ $node_count -eq 0 ]; then
  log "Did not find any nodes that were not 'master' or 'worker-lb' nodes, exiting"
  exit 1
else
  log "$node_count node(s) found"
fi

if [ $node_count -lt 10 ]; then
  total_mcps=$node_count
  mcp_node_count=1
  log "$total_mcps new MCP(s) required with 1 node in each"
else
  total_mcps=$((($node_count / 10) + ($node_count % 10 > 0)))
  log "$total_mcps new MCP(s) required"
fi

if [ $node_count -lt $total_mcps ]; then
  log "MCP_SIZE is greater than available nodes, exiting"
  exit 1
fi

mcp_list=()
mcp_deployment=1

# Deploy MCP's required
while [ $mcp_deployment -le $total_mcps ]; do
  export_label="upgrade$mcp_deployment"
  export CUSTOM_NAME=${export_label}
  export CUSTOM_VALUE=${export_label}
  export CUSTOM_LABEL=${export_label}
  log "Deploying new MCP ${export_label}"
  envsubst < mcp.yaml | oc apply -f -
  mcp_list+=(${export_label})
  ((mcp_deployment++))
done

# Label nodes in each new MCP
log "Applying custom labels to nodes in each new MCP"
nodes_labeled_mcp=1
element=0
node_element=0
i=0

while [ $nodes_labeled_mcp -le $total_mcps ]; do
  temp_node_list=()
  if [ $node_count -lt 10 ]; then
    temp_node_list+=(${node_list[$element]})
    ((element++))
  else
    temp_node_list+=(${node_list[@]:$element:$mcp_node_count})
    element=$(($element + $mcp_node_count))
  fi

  while [ $node_element -lt ${#temp_node_list[@]} ]; do
    oc label nodes ${temp_node_list[$node_element]} node-role.kubernetes.io/custom=${mcp_list[$i]}
    ((node_element++))
  done
  node_element=0
  ((i++))
  ((nodes_labeled_mcp++))
done

log "Completed applying custom labels to nodes in new MCP's"

# Calculate allocatable CPU per MCP
mcp_count_var=1
mcp_counter=0
temp_node_list=()
node_element=0
#allocation_calc_amounts=()

while [ $mcp_count_var -le $total_mcps ]; do
  log "Begining deployment of project and sample-app for MCP ${mcp_list[${mcp_counter}]}"
  nodes=$('oc get nodes --no-headers --selector=node-role.kubernetes.io/custom='${mcp_list[$mcp_counter]} | awk '{print $1 }')
  temp_node_list+=(${nodes[@]})
  node_count=${#temp_node_list[@]}
  allocation_amounts=()
  node_count_var=1
  while [ $node_count_var -le $node_count ]; do
    node_alloc_cpu=$(oc get ${temp_node_list[mcp_counter]} -o json | jq .status.allocatable.cpu)
    node_alloc_cpu_int=${node_alloc_cpu//[a-z]/}
    allocation_amounts+=($node_alloc_cpu_int)
    ((node_count_var++))
    ((node_element++))
  done
  node_count_var=1
  sum_alloc_cpu=$(IFS=+; echo "$((${allocation_amounts[*]}))")
  log "Total allocatable cpu ${mcp_list[$mcp_counter]} is $sum_alloc_cpu"
  calc=$(( sum_alloc_cpu / 2 ))
  new_allocatable="${calc}m"
  log "New calculated allocatable cpu to use in MCP ${mcp_list[$mcp_counter]} is $new_allocatable"
  #allocation_calc_amounts+=($new_allocatable)
  calc_replica=$(( $calc / 1000 ))
  log "$calc_replica replica(s) will be deployed in MCP ${mcp_list[$mcp_counter]} nodes"

  # Create new project per MCP
  new_project="${mcp_list[$mcp_counter]}"
  log "Creating new project ${new_project}"
  oc new-project $new_project

  # Export vars and deploy sample app
  export PROJECT=$new_project
  export REPLICAS=$calc_replica
  export NODE_SELECTOR_KEY="node-role.kubernetes.io/custom"
  export NODE_SELECTOR_VALUE=${mcp_list[${mcp_counter}]}
  log "Deploying $calc_replica replica(s) of the sample-app for MCP ${mcp_list[${mcp_counter}]}"
  oc apply -f deployment-sampleapp.yml

  # Unset vars and begin to loop to next MCP
  log "Completed sample-app deployment in ${mcp_list[${mcp_counter}]}"
  unset temp_node_list
  unset PROJECT
  unset REPLICAS
  unset NODE_SELECTOR_KEY
  unset NODE_SELECTOR_VALUE
  ((mcp_count_var++))
  ((mcp_counter++))
done
}

cleanup() {
  oc delete ns -l kube-burner-uuid=${UUID}
}
 
