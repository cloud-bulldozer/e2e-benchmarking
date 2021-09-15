#!/usr/bin/env bash

log() {
  echo ${bold}$(date -u):  ${@}${normal}
}

baremetal_upgrade_auxiliary() {
  log "---------------------Checking Env Vars---------------------"
  total_mcps=$TOTAL_MCPS
  mcp_node_count=$MCP_NODE_COUNT
  create_mcps_bool=${CREATE_MCPS_BOOL:=false}
  if [ ! -z $total_mcps ] && [ $total_mcps -eq 0 ]; then
    echo "TOTAL_MCPS env var was set to 0, exiting"
    exit 1
  fi
  if [ ! -z $mcp_node_count ] && [ $mcp_node_count -eq 0 ]; then
    echo "MCP_NODE_COUNT env var was set to 0, exiting"
    exit 1
  fi
  if [[ ! -z "$total_mcps" ]] && [[ ! $total_mcps =~ ^[0-9]+$ ]]; then
    echo "total_mcps input is not empty or not an integer, exiting"
    exit 1
  fi
  if [[ ! -z "$mcp_node_count" ]] && [[ ! $mcp_node_count =~ ^[0-9]+$ ]]; then
    echo "mcp_node_count input is not empty or not an integer, exiting"
    exit 1
  fi
  if [ "${create_mcps_bool}" == "true" ]; then
    mcp_bool="true"
    echo "CREATE_MCPS_BOOL was set. Creating new MCPs"
  else
    mcp_bool="false"
    echo "CREATE_MCPS_BOOL set to skip. Skipping MCP Creation"
  fi
  
  log "---------------------Retrieving Available Nodes---------------------"
  # Retrieve nodes in cluster
  echo "Retrieving all nodes in the cluster that do not have the role 'master' or 'worker-lb'"
  node_list=($(oc get nodes --no-headers | grep -v master | grep -v worker-lb | grep -v worker-rt | awk '{print $1}'))
  node_count=${#node_list[@]}

  # Check for 1 or more nodes to be used
  if [ $node_count -eq 0 ]; then
    echo "Did not find any nodes that were not 'master' or 'worker-lb' nodes, exiting"
    exit 1
  else
    echo "$node_count node(s) found"
  fi
  
  if [ $mcp_bool == "true" ]; then
    log "---------------------Calculating MCP count---------------------"
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
      

      # Calculate total nodes per MCP if only total MCP's are provided
      elif [ ! -z $total_mcps ] && [ -z $mcp_node_count ]; then
        if [ $total_mcps -gt $node_count ]; then
          echo "Supplied TOTAL_MCPS is greater than available nodes, exiting"
          exit 1
        else
          echo "Found TOTAL_MCPS value, but not MCP_NODE_COUNT, attempting to calculate MCP_NODE_COUNT with supplied TOTAL_MCPS"
          mcp_node_count=$((($node_count / $total_mcps) + ($node_count % $total_mcps > 0)))
          echo "$mcp_node_count node(s) required per MCP for supplied TOTAL_MCPS of $total_mcps with $node_count node(s) available"
        fi
      
      
      # Verify that TOTAL_MCPS and MCP_NODE_COUNT set equal available nodes
      elif [ ! -z $total_mcps ] && [ ! -z $mcp_node_count ]; then
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
  else
    log "---------------------Applying Custom Label to Availalbe Nodes---------------------"
    nodes_labeled=1
    element=0
  
    while [ $nodes_labeled -le $node_count ]; do
      oc label nodes ${node_list[$element]} node-role.kubernetes.io/custom=upgrade  --overwrite=true
      ((nodes_labeled++))
      ((element++))
    done
  fi
  
  if [ $mcp_bool == "true" ]; then
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
      exist=($(oc get project ${new_project} --ignore-not-found))
      if [ ! -z $exist ]; then
        echo "Project ${new_project} was found, attempting to delete"
        oc delete project ${new_project} --force --grace-period=0 --ignore-not-found
        phase=$(oc get project ${new_project} -o json --ignore-not-found | jq .status.phase)
        while [[ ${phase} == '"Terminating"' ]]; do
          check=($(oc get project ${new_project} --ignore-not-found))
          if [ ! -z $check ]; then
            phase=$(oc get project ${new_project} -o json --ignore-not-found | jq .status.phase)
            echo "Waiting for project ${new_project} to terminate"
            oc delete pods --all -n ${new_project} --force > /dev/null 2>&1
            sleep 5
          else
            echo "Project ${new_project} deleted"
            phase="complete"
          fi
        done
      else
        echo "Project ${new_project} not found"
      fi
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

      # Verify all pods are running
      echo "Waiting for all pods to spin up successfully in project ${mcp_list[${mcp_counter}]}"
      sleep 10
      running_pods=$(oc get pods -n ${mcp_list[${mcp_counter}]} --field-selector=status.phase==Running | wc -l)
      while [ $running_pods -le 1 ]; do
        running_pods=$(oc get pods -n ${mcp_list[${mcp_counter}]} --field-selector=status.phase==Running | wc -l)
      done
      while [ $running_pods -lt $calc_replica ]; do
        echo "Waiting for all pods to spin up successfully in project ${mcp_list[${mcp_counter}]}"
        sleep 5
        running_pods=$(oc get pods -n ${mcp_list[${mcp_counter}]} --field-selector=status.phase==Running | wc -l)
      done

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
  else
    log "---------------------Calculating Replica Count and Deploying---------------------"
    # Retrieve allocatable CPU across all available nodes
    nodes=($(oc get nodes --no-headers --selector=node-role.kubernetes.io/custom=upgrade| awk '{print $1 }'))
    node_count_var=1
    node_element=0
    allocation_amounts=()
    while [ $node_count_var -le $node_count ]; do
      node_alloc_cpu=$(oc get node ${node_list[${node_element}]} -o json | jq .status.allocatable.cpu)
      node_alloc_cpu_int=${node_alloc_cpu//[a-z]/}
      node_alloc_cpu_int_p1="${node_alloc_cpu_int%\"}"
      node_alloc_cpu_int_p2="${node_alloc_cpu_int_p1#\"}"
      allocation_amounts+=($node_alloc_cpu_int_p2)
      ((node_count_var++))
      ((node_element++))
    done
    
    # Calculate replica count
    sum_alloc_cpu=$(IFS=+; echo "$((${allocation_amounts[*]}))")
    echo "Total allocatable cpu is $sum_alloc_cpu"
    calc=$(( sum_alloc_cpu / 2 ))
    new_allocatable="${calc}m"
    echo "New calculated allocatable cpu to use is $new_allocatable"
    #allocation_calc_amounts+=($new_allocatable)
    calc_replica=$(( $calc / 1000 ))
    echo "$calc_replica replica(s) will be deployed"

    new_project="upgrade"
    echo "Removing project upgrade if it exists"
      exist=($(oc get project upgrade --ignore-not-found))
      if [ ! -z $exist ]; then
        echo "Project upgrade was found, attempting to delete"
        oc delete project upgrade --force --grace-period=0 --ignore-not-found
        phase=$(oc get project upgrade -o json --ignore-not-found | jq .status.phase)
        while [[ ${phase} == '"Terminating"' ]]; do
          check=($(oc get project upgrade --ignore-not-found))
          if [ ! -z $check ]; then
            phase=$(oc get project upgrade -o json --ignore-not-found | jq .status.phase)
            echo "Waiting for project upgrade to terminate"
            oc delete pods --all -n upgrade --force > /dev/null 2>&1
            sleep 5
          else
            echo "Project upgrade deleted"
            phase="complete"
          fi
        done
      else
        echo "Project upgrade not found"
      fi
      echo "Creating new project upgrade"
      oc new-project upgrade

    # Append information arrays to be used for mb json file
    project_list=("upgrade")
    replica_count=($calc_replica)

    # Export vars and deploy sample app
    export PROJECT="upgrade"
    export APP_NAME="sampleapp-upgrade"
    export REPLICAS=$calc_replica
    #export NODE_SELECTOR_KEY="node-role.kubernetes.io/custom"
    export NODE_SELECTOR_VALUE="upgrade"
    echo "Deploying $calc_replica replica(s) of the sample-app in project upgrade"
    envsubst < deployment-sampleapp.yml | oc apply -f -
    oc expose service samplesvc -n upgrade

    # Verify all pods are running
    echo "Waiting for all pods to spin up successfully in project upgrade"
    sleep 10
    running_pods=$(oc get pods -n upgrade --field-selector=status.phase==Running | wc -l)
    while [ $running_pods -le 1 ]; do
      running_pods=$(oc get pods -n upgrade --field-selector=status.phase==Running | wc -l)
    done
    while [ $running_pods -lt $calc_replica ]; do
      echo "Waiting for all pods to spin up successfully in project upgrade"
      sleep 5
      running_pods=$(oc get pods -n upgrade --field-selector=status.phase==Running | wc -l)
    done

    # Unset vars and begin to loop to next MCP
    echo "Completed ${APP_NAME} deployment in upgrade"

  fi
  

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
    namespace: default
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
  log "---------------------Deploy mb-pod---------------------"
  oc apply -f mb_pod.yml
  sleep 30
#   oc logs -n default mb-pod -f 
  }