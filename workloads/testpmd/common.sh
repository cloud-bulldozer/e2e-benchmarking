source env.sh
source ../../utils/benchmark-operator.sh

# global variables
length=0
numa_node=1
numa_nodes_0=()
numa_nodes_1=()
cpus_0=()
cpus_1=()
isolated=()
reserved=()
nic=""
testpmd_workers=()

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

log() {
  echo ${bold}$(date -u):  ${@}${normal}
}

check_cluster_present() {
  oc get clusterversion
  if [ $? -ne 0 ]; then
    log "Workload Failed for cloud $cloud_name, Unable to connect to the cluster"
    exit 1
  fi
  cluster_version=$(oc get clusterversion --no-headers | awk '{ print $2 }')
}

check_cluster_health() {
  if [[ ${CERBERUS_URL} ]]; then
    response=$(curl ${CERBERUS_URL})
    if [ "$response" != "True" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
  fi
}

export_defaults() {
  CRD=${CRD:-ripsaw-testpmd-crd.yaml}
  MCP=${MCP:-machineconfigpool.yaml}
  PFP=${PFP:-perf_profile.yaml}
  NNP=${NNP:-sriov_network_node_policy.yaml}
  export COMPARE=${COMPARE:=false}
  export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)

  #Check to see if the infrastructure type is baremetal to adjust script as necessary 
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "BareMetal infastructure: setting isBareMetal accordingly"
    export isBareMetal=true
  else
    export isBareMetal=false
  fi

  cloud_name=$1
  if [ "$cloud_name" == "" ]; then
    export cloud_name="${network_type}_${platform}_${cluster_version}"
  fi

  if [[ ${COMPARE} == "true" ]]; then
    echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
  else
    echo $cloud_name > uuid.txt
  fi

  #If using baremetal we use different query to find worker nodes
  if [[ "${isBareMetal}" == "true" ]]; then
     #Installing python3.8
     sudo yum -y install python3.8
     sudo alternatives --set python3 /usr/bin/python3.8
  fi

} 


deploy_perf_profile() {
  # find suitable nodes
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "Trying to find 2 suitable nodes only for testpmd"
    worker_count=0
    workers=$(oc get node -o name --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker= | head -${NODE_COUNT} | sed -e 's/^node\///')
    # turn it into an array
    workers=($workers) 
    if [[ ${#workers[@]} -lt 1 ]] ; then
      log "Not enough worker nodes for the testpmd workload available, bailing!"
      exit 1
    fi
    while [[ $worker_count -lt 2 ]]; do 
	worker=${workers[$worker_count]}
	worker_ip=$(oc get node ${workers[$worker_count]} -o json | jq -r ".status.addresses[0].address" | grep 192 )
        if [[ ! -z "$worker_ip" ]]; then 
	  testpmd_workers+=($worker)
	  ((worker_count++))
        fi
    done
  fi
  
  # get the interface's NUMA zone
  if [ ! -f /home/kni/.ssh/id_rsa ] ; then
	  log "id_rsa for user kni doesn't exist, bailing!"
	  exit 1
  fi
  for w in ${testpmd_workers[@]}; do
        nic=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "sudo ovs-vsctl list-ports br-ex | head -1")
	export sriov_nic=$nic
	log "Getting the NUMA zones for the NICs"
	nic_numa+=($(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "cat /sys/class/net/"$nic"/device/numa_node"))
        # also get the CPU alignment
        numa_nodes_0=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "lscpu | grep '^NUMA node0' | cut -d ':' -f 2")
        numa_nodes_1=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "lscpu | grep '^NUMA node1' | cut -d ':' -f 2" )
  done
  
  # pin testpmd and trex to nodes
  export PIN_TESTPMD=${testpmd_workers[0]}
  export PIN_TREX=${testpmd_workers[1]}

  # check if the entries in nic_numa are all identical
  if [ "${#nic_numa[@]}" -gt 0 ] && [ $(printf "%s\000" "${nic_numa[@]}" | LC_ALL=C sort -z -u | grep -z -c .) -eq 1 ] ; then
          log "The numa_node for all selected NICs is identical, continuing."
	  numa_node=${nic_numa[0]}
	  export numa_node=$numa_node
  else
          log "The numa_nodes for the selected NICs are different, bailing out!"
          exit 1
  fi
   
  # convert strings into arrays so we can split easier
  for entry in $(IFS=','; echo $numa_nodes_0); do
    cpus_0+=($entry)
  done
  for entry in $(IFS=','; echo $numa_nodes_1); do
    cpus_1+=($entry)
  done

  # numa node is 0
  if [[ $numa_node == 0 ]]; then
    # all cpus in cpus_0 - 2 for housekeeping go to isolated
    log "Numa node is 0"
    export SOCKET_MEMORY="1024,0"
    num_cpus=${#cpus_0[@]}
    count=0
    max=$((($num_cpus -8) / 2))
    max_isol=$((max -2))
    for cpu in ${cpus_0[@]}; do
      if [ $count -le $max_isol ]; then
        # add the cpu to the isolated nodes
        isolated+=($cpu)
      elif [ $count -gt $max_isol ] && [ $count -le $max ]; then
        # add the cpu to the reserved nodes
        reserved+=($cpu)
      fi
        count=$((count+1))
    done

    # add the remaining CPUs to reserved
    num_cpus=${#cpus_1[@]}
    count=0
    max=$((($num_cpus -8) / 2))
    for cpu in ${cpus_1[@]}; do
      if [ $count -le $max ] ; then
        # add the cpu to the reserved nodes
        reserved+=($cpu)
      fi
      count=$((count+1))
    done
  fi

  # numa node is 1
  if [[ $numa_node == 1 ]]; then
    # all cpus in cpus_1 - 2 for housekeeping go to isolated
    log "Numa node is 1"
    export SOCKET_MEMORY="0,1024"
    num_cpus=${#cpus_1[@]}
    count=0
    max=$((($num_cpus -8) / 2))
    #echo max is $max
    max_isol=$((max - 2))
    for cpu in ${cpus_1[@]}; do
      if [ $count -le $max_isol ]; then
        # add the cpu to the isolated nodes
        isolated+=($cpu)
      elif [ $count -gt $max_isol ] && [ $count -le $max ]; then
        # add the cpu to the reserved nodes for housekeeping
        reserved+=($cpu)
      fi
        count=$((count+1))
    done

    # add the remaining CPUs to reserved
    num_cpus=${#cpus_0[@]}
    count=0
    max=$((($num_cpus -8) / 2))
    #echo max: $max
    for cpu in ${cpus_0[@]}; do
      if [ $count -le $max ] ; then
      # add the cpu to the reserved nodes
      reserved+=($cpu)
      fi
      count=$((count+1))
    done
  fi

  # templatize the perf profile and the sriov network node policy
  reserved_string=$(echo ${reserved[@]} | sed -s 's/ /,/g')
  isolated_string=$(echo ${isolated[@]} | sed -s 's/ /,/g')
  export isolated_cpus=$isolated_string
  export reserved_cpus=$reserved_string
 
  # label the two nodes for the performance profile
  log "Labeling -rt nodes"
  for w in ${testpmd_workers[@]}; do
    oc label node $w node-role.kubernetes.io/worker-rt="" --overwrite=true
  done

  # create the machineconfigpool
  log "Create the MCP"
  envsubst < $MCP | oc apply -f -
  sleep 30
  if [ $? -ne 0 ] ; then
    log "Couldn't create the MCP, exiting!"
    exit 1
  fi

  # add the label to the MCP pool 
  log "Labeling the MCP"
  oc label mcp worker-rt machineconfiguration.openshift.io/role=worker-rt --overwrite=true
  if [ $? -ne 0 ] ; then
    log "Couldn't label the MCP, exiting!"
    exit 1
  fi

  # apply the performanceProfile
  log "Applying the performanceProfile"
  envsubst < $PFP | oc apply -f -
  if [ $? -ne 0 ] ; then
    log "Couldn't apply the performance profile, exiting!"
    exit 1
  fi
  
  # We need to wait for the nodes with the perfProfile applied to to reboot
  # this is a catchall approach, we sleep for 60 seconds and check the status of the nodes
  # if they're ready, we'll continue. Should the performance profile require reboots, that will have
  # started within the 60 seconds
  iterations=0
  log "Sleeping for 60 seconds"
  sleep 60
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  while [[ $readycount -lt 2 ]]; do
    if [[ $iterations -gt $PROFILE_TIMEOUT ]]; then
      log "Waited for the -rt MCP for $PROFILE_TIMEOUT minutes, bailing!"
      exit 124
    fi
    log "Waiting for -rt nodes to become ready again after the performance-profile has been deployed, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
    iterations=$((iterations+1))
  done

  # apply the node policy
  envsubst < $NNP | oc apply -f -
  if [ $? -ne 0 ] ; then
    log "Could't create the network node policy, exiting!"
    exit 1
  fi
  # we need to wait for the second reboot
  iterations=0
  log "Sleeping for 60 seconds"
  sleep 60
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  while [[ $readycount -lt 2 ]]; do
    if [[ $iterations -gt $PROFILE_TIMEOUT ]]; then
      log "Waited for the -rt MCP for $PROFILE_TIMEOUT minutes, bailing"
      exit 124
    fi
    log "Waiting for -rt nodes to become ready again after the sriov-network-policy has been deployed, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
    iterations=$((iterations+1))
  done

  # create the network
  oc apply -f sriov_network.yaml
  if [ $? -ne 0 ] ; then
    log "Could not create the sriov network, exiting!"
    exit 1
  fi
}

cleanup_network() {
  # cleaning up for later tasks, removing the perf-profile, the network-node-policy, the mcp and the network
  # also removing the labels on the nodes
  log "Removing the labels from the nodes"
  for w in ${testpmd_workers[@]}; do
    oc label node $w node-role.kubernetes.io/worker-rt-
  done
  log "Removing the MCP"
  oc delete -f machineconfigpool.yaml
  log "Removing the performance profile"
  oc delete -f perf_profile.yaml
  log "Removing the sriov network node policy"
  oc delete -f sriov_network_node_policy.yaml
  log "Removing the sriov network"
  oc delete -f sriov_network.yaml
  iterations=0
  readycount=$(oc get mcp worker --no-headers | awk '{print $7}')
  while [[ $readycount -ne 2 ]]; do
    if [[ $iterations -gt 40 ]]; then
      log "Waited for the -rt MCP for 40 minutes, bailing"
      exit 124
    fi
    log "Waiting for worker nodes to become ready again after the sriov-network-policy has been deployed, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker --no-headers | awk '{print $7}')
    iterations=$((iterations+1))
  done

}

deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
}

run_workload() {
  log "Deploying testpmd benchmark"
  local TMPCR=$(mktemp)
  envsubst < $1 > ${TMPCR}
  run_benchmark ${TMPCR} ${TEST_TIMEOUT}
  local rc=$?
  if [[ ${TEST_CLEANUP} == "true" ]]; then
    log "Cleaning up benchmark"
    kubectl delete -f ${TMPCR}
  fi
  return ${rc}
}

check_logs_for_errors() {
client_pod=$(oc get pods -n benchmark-operator --no-headers | grep -i running | awk '{print $1}' | grep trex-traffic-gen | awk 'NR==1{print $1}')
if [ ! -z "$client_pod" ]; then
  num_critical=$(oc logs ${client_pod} -n benchmark-operator | grep CRITICAL | wc -l)
  if [ $num_critical -gt 3 ] ; then
    log "Encountered CRITICAL condition more than 3 times in trex-traffic-gen pod  logs"
    log "Log dump of trex-traffic-gen pod"
    oc logs $client_pod -n benchmark-operator
    delete_benchmark
    exit 1
  fi
fi
}

wait_for_benchmark() {
  testpmd_state=1
  for i in {1..480}; do # 2hours
    update
    if [ "${benchmark_state}" == "Error" ]; then
      log "Cerberus status is False, Cluster is unhealthy"
      exit 1
    fi
    oc describe -n benchmark-operator benchmarks/testpmd-benchmark-$UUID | grep State | grep Complete
    if [ $? -eq 0 ]; then
      log "testpmd workload done!"
      testpmd_state=$?
      break
    fi
    update
    log "Current status of the ${WORKLOAD} benchmark is ${uline}${benchmark_state}${normal}"
    check_logs_for_errors
    sleep 30
  done

  if [ "$testpmd_state" == "1" ] ; then
    log "Workload failed"
    exit 1
  fi
}

assign_uuid() {
  update
  compare_testpmd_uuid=${benchmark_uuid}
  if [[ ${COMPARE} == "true" ]] ; then
    echo ${baseline_testpmd_uuid},${compare_testpmd_uuid} >> uuid.txt
  else
    echo ${compare_testpmd_uuid} >> uuid.txt
  fi
}

run_benchmark_comparison() {
  log "Beginning benchmark comparison"
  ../../utils/touchstone-compare/run_compare.sh testpmd ${baseline_testpmd_uuid} ${compare_testpmd_uuid} 
  log "Finished benchmark comparison"
}

generate_csv() {
  log "Generating CSV"
  # tbd
}

delete_benchmark() {
  oc delete benchmarks.ripsaw.cloudbulldozer.io/testpmd-benchmark -n benchmark-operator
}

update() {
  benchmark_state=$(oc get benchmarks.ripsaw.cloudbulldozer.io/testpmd-benchmark -n benchmark-operator -o jsonpath='{.status.state}')
  benchmark_uuid=$(oc get benchmarks.ripsaw.cloudbulldozer.io/testpmd-benchmark -n benchmark-operator -o jsonpath='{.status.uuid}')
  benchmark_current_pair=$(oc get benchmarks.ripsaw.cloudbulldozer.io/testpmd-benchmark -n benchmark-operator -o jsonpath='{.spec.workload.args.pair}')
}

print_uuid() {
  log "Logging uuid.txt"
  cat uuid.txt
}


export TERM=screen-256color
bold=$(tput bold)
uline=$(tput smul)
normal=$(tput sgr0)
python3 -m pip install -r requirements.txt | grep -v 'already satisfied'
check_cluster_present
export_defaults
#init_cleanup
check_cluster_health
deploy_perf_profile
deploy_operator
run_workload ripsaw-testpmd-crd.yaml
#wait_for_benchmark
#delete_benchmark
#cleanup_network
