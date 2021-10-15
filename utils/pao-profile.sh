#!/bin/bash

check_for_perf_profile() {
  if [[ $(oc get performanceprofile --no-headers | awk '{print $1}') == "benchmark-performance-profile-0" ]]; then
	log "Performance profile already exists"
	return true
  else
        log "Performance profile not found"
	return false
  fi
}

deploy_perf_profile() {
  # find suitable nodes
  if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
    log "Trying to find 2 suitable nodes only for testpmd"
    # iterate over worker nodes bareMetalHandles until we have at least 2 
    worker_count=0
    workers=$(oc get nodes | grep -v master | grep -v worker-lb | grep -v custom | grep -v NotReady | grep ^worker | awk '{print $1}')
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
  for w in ${testpmd_workers[@]}; do
        nic=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "sudo ovs-vsctl list-ports br-ex | head -1")
        export sriov_nic=$nic
        log "Getting the NUMA zones for the NICs"
        nic_numa+=($(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "cat /sys/class/net/"$nic"/device/numa_node"))
        # also get the CPU alignment
        numa_nodes_0=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "lscpu | grep '^NUMA node0' | cut -d ':' -f 2")
        numa_nodes_1=$(ssh -i /home/kni/.ssh/id_rsa -o StrictHostKeyChecking=no core@$w "lscpu | grep '^NUMA node1' | cut -d ':' -f 2" )
  done

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
  log "Sleeping for 60 seconds"
  sleep 60
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  while [[ $readycount -ne 2 ]]; do
    log "Waiting for -rt nodes to become ready again after the performance-profile has been deployed, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  done

  # apply the node policy
  envsubst < $NNP | oc apply -f -
  if [ $? -ne 0 ] ; then
    log "Could't create the network node policy, exiting!"
    exit 1
  fi
  # we need to wait for the second reboot
  log "Sleeping for 60 seconds"
  sleep 60
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  while [[ $readycount -ne 2 ]]; do
    log "Waiting for -rt nodes to become ready again after the sriov-network-policy has been deployed, sleeping 1 minute"
    sleep 60
    readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  done

  # create the network
  oc apply -f sriov_network.yaml
  if [ $? -ne 0 ] ; then
    log "Could not create the sriov network, exiting!"
    exit 1
  fi
}

