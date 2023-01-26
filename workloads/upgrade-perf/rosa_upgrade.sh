#!/usr/bin/env bash
export rosa_environment=${ROSA_ENVIRONMENT:=staging}
# Nightly versions cannot be upgraded, only valid channels for upgrading are stable and candidate
export rosa_version_channel=${ROSA_VERSION_CHANNEL:=stable}
_es_index=${ES_INDEX:=managedservices-timings}
export control_plane_waiting_iterations=${ROSA_CONTROL_PLANE_WAITING:=90}
export waiting_per_worker=${ROSA_WORKER_UPGRADE_TIME:=5}

rosa_upgrade(){
  if [ ${rosa_version_channel} == "nightly" ] ; then
    echo "ERROR: Invalid channel group. Nightly versions cannot be upgraded. Exiting..."
    exit 1
  fi
  echo "ROSA Cluster: ${ROSA_CLUSTER_NAME}"
  echo "ROSA Environment: ${rosa_environment}"
  echo "ROSA Channel Group: ${rosa_version_channel}"
  export HOME=${HOME:=$PWD}
  rosa login --env=${rosa_environment} --token=${ROSA_TOKEN}
  if [ $(rosa list clusters | awk '{print $2}' | sed -e 1d | grep ${ROSA_CLUSTER_NAME}) != ${ROSA_CLUSTER_NAME} ] ; then
    echo "ERROR: Cluster ${ROSA_CLUSTER_NAME} not found on rosa list clusters results. Exiting..."
    exit 1
  fi
  if [ ! -z ${LATEST} ] && [ -z ${TOVERSION} ] ; then
    echo "INFO: Getting latest version available to upgrade..."
    VERSION=$(rosa list upgrade -c ${ROSA_CLUSTER_NAME} | sed -e 1d | head -1 | awk '{print $1}')
  elif [ ! -z ${TOVERSION} ] && [ -z ${LATEST} ] ; then
    echo "INFO: Checking if ${TOVERSION} version is available to upgrade..."
    VERSION=$(rosa list upgrade -c ${ROSA_CLUSTER_NAME} | sed -e 1d | awk '{print $1}' | grep ${TOVERSION})
  elif [ -z ${TOVERSION} ] && [ -z ${LATEST} ] ; then
    echo "ERROR: Only LATEST or TOVERSION can be defined. Exiting..."
    exit 1
  else
    echo "ERROR: Missing upgrade strategy. No LATEST or TOVERSION are defined. Exiting..."
    exit 1
  fi
  if [ -z ${VERSION} ] ; then
    echo "ERROR: No version to upgrade found running rosa list upgrade -c ${ROSA_CLUSTER_NAME}"
    exit 1
  else
    echo "INFO: Upgrading cluster to ${VERSION} version..."
  fi
  CURRENT_VERSION=$(oc get clusterversion | grep ^version | awk '{print $2}')
  # Add -m auto flag when cluster is sts
  if [[ $(rosa describe cluster -c ${ROSA_CLUSTER_NAME} -o json | jq -r '.aws | select(.sts != "null")') != "" ]]; then
    rosa upgrade cluster -c ${ROSA_CLUSTER_NAME} --version=${VERSION} -y --schedule-date $(date +%Y-%m-%d) --schedule-time $(date -u --date="+7 minutes" +%H:%M) -m auto
  else
    rosa upgrade cluster -c ${ROSA_CLUSTER_NAME} --version=${VERSION} -y --schedule-date $(date +%Y-%m-%d) --schedule-time $(date -u --date="+7 minutes" +%H:%M)
  fi
  # Sleep 7 minutes, rosa upgrade dont let to schedule an upgrade in less than 5 minutes from now
  sleep 420
  oc delete pods -n openshift-insights --all
  oc delete pods -n openshift-managed-upgrade-operator --all
  rosa_control_plane_upgrade_active_waiting ${VERSION}
  if [ $? -eq 0 ] ; then
    CONTROLPLANE_UPGRADE_RESULT="OK"
  else
    CONTROLPLANE_UPGRADE_RESULT="Failed"
  fi
  rosa_workers_active_waiting
  if [ $? -eq 0 ] ; then
    WORKERS_UPGRADE_RESULT="OK"
  else
    WORKERS_UPGRADE_RESULT="Failed"
  fi
  rosa_upgrade_index_results ${CONTROLPLANE_UPGRADE_DURATION} ${CONTROLPLANE_UPGRADE_RESULT} ${WORKERS_UPGRADE_DURATION} ${WORKERS_UPGRADE_RESULT} ${CURRENT_VERSION} ${VERSION}
  exit 0
}

rosa_workers_active_waiting(){
  start_time=$(date +%s)
  WORKERS=$(oc get node --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker="" 2>/dev/null | wc -l)
  # Giving waiting_per_worker minutes per worker
  ITERATIONWORKERS=0
  while [ ${ITERATIONWORKERS} -le $(( ${WORKERS}*${waiting_per_worker} )) ] ; do
    if [ $(rosa describe cluster -c ${ROSA_CLUSTER_NAME} | grep ^Scheduled | wc -l) -ne 1 ] ; then
      echo "INFO: Upgrade finished for ROSA, continuing..."
      end_time=$(date +%s)
      export WORKERS_UPGRADE_DURATION=$((${end_time} - ${start_time}))
      return 0
    else
      LASTSTATUS=$(oc logs $(oc get pods -n openshift-managed-upgrade-operator -o Name | grep -v catalog) -n openshift-managed-upgrade-operator | grep "workers are upgraded" | tail -1)
      echo "INFO: ${ITERATIONWORKERS}/$(( ${WORKERS}*${waiting_per_worker} )). Last Update: ${LASTSTATUS}."
      echo "INFO: Waiting 60 seconds for the next check..."
      ITERATIONWORKERS=$((${ITERATIONWORKERS}+1))
      sleep 60
    fi
  done
  echo "ERROR: ${ITERATIONWORKERS}/$(( ${WORKERS}*${waiting_per_worker} )). ROSA workers upgrade not finished after $(( ${WORKERS}*${waiting_per_worker} )) iterations. Exiting..."
  end_time=$(date +%s)
  export WORKERS_UPGRADE_DURATION=$((${end_time} - ${start_time}))
  oc logs $(oc get pods -n openshift-managed-upgrade-operator -o Name | grep -v catalog) -n openshift-managed-upgrade-operator
  rosa describe cluster -c ${ROSA_CLUSTER_NAME}
  return 1
}

rosa_control_plane_upgrade_active_waiting(){
  # Giving control_plane_waiting_iterations minutes for controlplane upgrade
  start_time=$(date +%s)
  ITERATIONS=0
  while [ ${ITERATIONS} -le ${control_plane_waiting_iterations} ] ; do
    VERSION_STATUS=($(oc get clusterversion | sed -e 1d | awk '{print $2" "$3" "$4}'))
    if [ ${VERSION_STATUS[0]} == $1 ] && [ ${VERSION_STATUS[1]} == "True" ] && [ ${VERSION_STATUS[2]} == "False" ] ; then
      # Version is upgraded, available=true, progressing=false -> Upgrade finished
      echo "INFO: OCP upgrade to $1 is finished for OCP, now waiting for ROSA..."
      end_time=$(date +%s)
      export CONTROLPLANE_UPGRADE_DURATION=$((${end_time} - ${start_time}))
      return 0
    else
      echo "INFO: ${ITERATIONS}/${control_plane_waiting_iterations}. AVAILABLE: ${VERSION_STATUS[1]}, PROGRESSING: ${VERSION_STATUS[2]}. Waiting 60 seconds for the next check..."
      ITERATIONS=$((${ITERATIONS}+1))
      sleep 60
    fi
  done
  echo "ERROR: ${ITERATIONS}/${control_plane_waiting_iterations}. OCP Version is ${VERSION_STATUS[0]}, not upgraded to $1 after ${control_plane_waiting_iterations} iterations. Exiting..."
  oc get clusterversion
  end_time=$(date +%s)
  export CONTROLPLANE_UPGRADE_DURATION=$((${end_time} - ${start_time}))
  return 1
}

rosa_upgrade_index_results(){
  if [ $(oc get cloudcredential -o json 2>/dev/null | jq -r '.items[].spec.credentialsMode') == "Manual" ] ; then
    AWS_AUTH="sts"
  else
    AWS_AUTH="iam"
  fi
  METADATA=$(grep -v "^#" << EOF
{
"uuid" : "${_uuid}",
"platform": "ROSA",
"cluster_name": "${ROSA_CLUSTER_NAME}",
"network_type": "$(oc get network cluster -o json 2>/dev/null | jq -r .status.networkType)",
"controlplane_upgrade_duration": "$1",
"workers_upgrade_duration": "$3",
"from_version": "$5",
"to_version": "$6",
"controlplane_upgrade_result": "$2",
"workers_upgrade_result": "$4",
"master_count": "$(oc get node -l node-role.kubernetes.io/master= --no-headers 2>/dev/null | wc -l)",
"worker_count": "$(oc get node --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker="" 2>/dev/null | wc -l)",
"infra_count": "$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
"workload_count": "$(oc get node -l node-role.kubernetes.io/workload= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
"total_node_count": "$(oc get nodes 2>/dev/null | wc -l)",
"ocp_cluster_name": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"timestamp": "$(date +%s%3N)",
"cluster_version": "$5",
"cluster_major_version": "$(echo $5 | awk -F. '{print $1"."$2}')",
"aws_authentication_method" : "${AWS_AUTH}"
}
EOF
)
  printf "Indexing installation timings to ${ES_SERVER}/${_es_index}"
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${_es_index}/_doc -d "${METADATA}" -o /dev/null
  return 0
}
