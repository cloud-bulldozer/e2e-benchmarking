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
    echo "Another kube-burner benchmark is running at the moment" && exit 1
    oc get benchmark -n benchmark-operator
  fi
}

baremetal_upgrade_auxiliary() {
  log "---------------------Calculating MCP count---------------------"
  total_mcps=$TOTAL_MCPS
  mcp_node_count=$MCP_NODE_COUNT

  if [ ! -z $total_mcps ] && [ $total_mcps -eq 0 ]; then
    echo "TOTAL_MCPS env var was set to 0, exiting"
    exit 1
  fi
  if [ ! -z $mcp_node_count ] && [ $mcp_node_count -eq 0 ]; then
    echo "MCP_NODE_COUNT env var was set to 0, exiting"
    exit 1
  fi

  # Retrieve nodes in cluster
  echo "Retrieving all nodes in the cluster that do not have the role 'master' or 'worker-lb'"
  node_list=($(oc get nodes --no-headers | grep -v master | grep -v worker-lb | awk '{print $1}'))
  node_count=${#node_list[@]}

  # Check for 1 or more nodes to be used
  if [ $node_count -eq 0 ]; then
    echo "Did not find any nodes that were not 'master' or 'worker-lb' nodes, exiting"
    exit 1
  else
    echo "$node_count node(s) found"
  fi

  # Use Defaults if TOTAL_MCPS and MCP_NODE_COUNT not set
  if [ -z $total_mcps ] && [ -z $mcp_node_count ]; then
    echo "TOTAL_MCPS and MCP_NODE_COUNT not set, calculating defaults!"
    if [ $node_count -le 10 ]; then
      total_mcps=$node_count
      mcp_node_count=1
      echo "10 or less nodes found, defaulting new MCP(s) to node count: $total_mcps new MCP(s) required with 1 node in each"
      defaults="true"
    else
      echo "Calculating number of MCP's required with a default of 10 nodes per MCP"
      mcp_node_count=10
      total_mcps=$((($node_count / 10) + ($node_count % 10 > 0)))
      echo "$total_mcps new MCP(s) required"
    fi
  else

    # Calculate total MCP's needed if only MCP_NODE_COUNT are provided
    if [ -z $total_mcps ] && [ ! -z $mcp_node_count ]; then
      if [ $mcp_node_count -gt $node_count ]; then
        echo "Supplied MCP_NODE_COUNT is greater than available nodes, exiting"
        exit 1
      else
        echo "Found MCP_NODE_COUNT value, but not TOTAL_MCPS, attempting to calculate TOTAL_MCPS with supplied MCP_NODE_COUNT"
        total_mcps=$((($node_count / $mcp_node_count) + ($node_count % $mcp_node_count > 0)))
        echo "$total_mcps new MCP(s) required for supplied MCP_NODE_COUNT of $mcp_node_count with $node_count node(s) available"
      fi
    fi

    # Calculate total nodes per MCP if only total MCP's are provided
    if [ ! -z $total_mcps ] && [ -z $mcp_node_count ]; then
      if [ $total_mcps -gt $node_count ]; then
        echo "Supplied TOTAL_MCPS is greater than available nodes, exiting"
        exit 1
      else
        echo "Found TOTAL_MCPS value, but not MCP_NODE_COUNT, attempting to calculate MCP_NODE_COUNT with supplied TOTAL_MCPS"
        mcp_node_count=$((($node_count / $total_mcps) + ($node_count % $total_mcps > 0)))
        echo "$mcp_node_count node(s) required per MCP for supplied TOTAL_MCPS of $total_mcps with $node_count node(s) available"
      fi
    fi
    
    # Verify that TOTAL_MCPS and MCP_NODE_COUNT set equal available nodes
    if [ ! -z $total_mcps ] && [ ! -z $mcp_node_count ]; then
      if [ $((($total_mcps * $mcp_node_count))) -ne $node_count ]; then
        echo "The product of TOTAL_MCPS and MCP_NODE_COUNT supplied values does not equal available nodes, unless node count is already known, please set one or the other"
        exit 1
      fi
    fi
  fi

  mcp_list=()
  mcp_deployment=1

  # Deploy MCP's required
  log "---------------------Creating new MCPs---------------------"
  while [ $mcp_deployment -le $total_mcps ]; do
    export_label="upgrade$mcp_deployment"
    export CUSTOM_NAME=${export_label}
    export CUSTOM_VALUE=${export_label}
    export CUSTOM_LABEL=${export_label}
    echo "Removing MCP ${export_label} if it exists"
    oc delete mcp ${export_label} --ignore-not-found
    echo "Deploying new MCP ${export_label}"
    envsubst < mcp.yaml | oc apply -f -
    mcp_list+=(${export_label})
    ((mcp_deployment++))
  done

  # Label nodes in each new MCP
  log "---------------------Applying custom labels to nodes in each new MCP---------------------"
  nodes_labeled_mcp=1
  element=0
  node_element=0
  i=0

  while [ $nodes_labeled_mcp -le $total_mcps ]; do
    temp_node_list=()
    if [ "$defaults" = "true" ]; then
      temp_node_list+=(${node_list[$element]})
      ((element++))
    else
      temp_node_list+=(${node_list[@]:$element:$mcp_node_count})
      element=$(($element + $mcp_node_count))
    fi

    while [ $node_element -lt ${#temp_node_list[@]} ]; do
      oc label nodes ${temp_node_list[$node_element]} node-role.kubernetes.io/custom=${mcp_list[$i]}  --overwrite=true
      ((node_element++))
    done
    node_element=0
    temp_node_list=()
    ((i++))
    ((nodes_labeled_mcp++))
  done

  echo "Completed applying custom labels to nodes in new MCP's"

  # Calculate allocatable CPU per MCP
  log "---------------------Calculating Replica Count and Deploy---------------------"
  mcp_count_var=1
  mcp_counter=0
  temp_node_list_counter=0
  temp_node_list=()
  node_element=0
  #allocation_calc_amounts=()

  # Store information to be used when creating json file for mb
  project_list=()
  replica_count=()

  while [ $mcp_count_var -le $total_mcps ]; do
    echo "Begining deployment of project and sample-app for MCP ${mcp_list[${mcp_counter}]}"
    nodes=($(oc get nodes --no-headers --selector=node-role.kubernetes.io/custom=${mcp_list[${mcp_counter}]} | awk '{print $1 }'))
    temp_node_list+=(${nodes[@]})
    node_count=${#temp_node_list[@]}
    allocation_amounts=()
    node_count_var=1
    while [ $node_count_var -le $node_count ]; do
      node_alloc_cpu=$(oc get node ${temp_node_list[${temp_node_list_counter}]} -o json | jq .status.allocatable.cpu)
      node_alloc_cpu_int=${node_alloc_cpu//[a-z]/}
      node_alloc_cpu_int_p1="${node_alloc_cpu_int%\"}"
      node_alloc_cpu_int_p2="${node_alloc_cpu_int_p1#\"}"
      allocation_amounts+=($node_alloc_cpu_int_p2)
      ((temp_node_list_counter++))
      ((node_count_var++))
      ((node_element++))
    done
    node_count_var=1
    temp_node_list_counter=0
    sum_alloc_cpu=$(IFS=+; echo "$((${allocation_amounts[*]}))")
    echo "Total allocatable cpu ${mcp_list[$mcp_counter]} is $sum_alloc_cpu"
    calc=$(( sum_alloc_cpu / 2 ))
    new_allocatable="${calc}m"
    echo "New calculated allocatable cpu to use in MCP ${mcp_list[$mcp_counter]} is $new_allocatable"
    #allocation_calc_amounts+=($new_allocatable)
    calc_replica=$(( $calc / 1000 ))
    echo "$calc_replica replica(s) will be deployed in MCP ${mcp_list[$mcp_counter]} nodes"

    # Create new project per MCP
    new_project="${mcp_list[$mcp_counter]}"
    echo "Removing project ${new_project} if it exists"
    oc delete project ${new_project} --force --grace-period=0 --ignore-not-found
    echo "Sleeping for 30 seconds to allow forced project deletion to complete successfully if project was found"
    oc delete pods --all -n ${new_project} --force > /dev/null 2>&1
    sleep 30
    echo "Creating new project ${new_project}"
    oc new-project $new_project

    # Append information arrays to be used for mb json file
    project_list+=($new_project)
    replica_count+=($calc_replica)

    # Export vars and deploy sample app
    export PROJECT=$new_project
    export APP_NAME="sampleapp-${new_project}"
    export REPLICAS=$calc_replica
    #export NODE_SELECTOR_KEY="node-role.kubernetes.io/custom"
    export NODE_SELECTOR_VALUE=${mcp_list[${mcp_counter}]}
    echo "Deploying $calc_replica replica(s) of the sample-app for MCP ${mcp_list[${mcp_counter}]}"
    envsubst < deployment-sampleapp.yml | oc apply -f -
    oc expose service samplesvc -n $new_project

    # Unset vars and begin to loop to next MCP
    echo "Completed ${APP_NAME} deployment in ${mcp_list[${mcp_counter}]}"
    unset temp_node_list
    unset PROJECT
    unset REPLICAS
    unset NODE_SELECTOR_KEY
    unset NODE_SELECTOR_VALUE
    ((mcp_count_var++))
    ((mcp_counter++))
  done

  log "---------------------Creating request.json---------------------"
  rm configmap.yml --force
  requests=${#project_list[@]}
  iterations=1
  element=0

  cat >> configmap.yml << EOF
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: request-configmap
    labels:
      app: mb-pod
  data:
    requests.json: |
       [
EOF

  while [ $iterations -le $requests ]; do
    host=($(oc get route samplesvc -n ${project_list[$element]} -ojson | jq .spec.host))
    clients=${replica_count[$element]}

    cat >> configmap.yml << EOF
          {
            "scheme": "http",
            "host": ${host},
            "port": 80,
            "method": "GET",
            "path": "/",
            "delay": {
              "min": 1000,
              "max": 2000
            },
            "keep-alive-requests": 100,
            "clients": ${clients}
          },
EOF
  ((iterations++))
  ((element++))
  done

  cat >> configmap.yml << EOF
        ]
EOF
  
  cat configmap.yml
  oc apply -f configmap.yml
  echo "sleeping for 1 minute to allow all sample-app pods to spin up"
  sleep 60
  log "---------------------Deploy mb-pod---------------------"
  oc apply -f mb_pod.yml
  sleep 30
  oc logs mb-pod -f 2>&1 | tee response.csv
  }

cleanup() {
  oc delete ns -l kube-burner-uuid=${UUID}
}
