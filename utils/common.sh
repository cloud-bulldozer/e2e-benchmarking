#!/usr/bin/env bash

##############################################################################
# Prints log messages
# Arguments:
#   Log string
##############################################################################
log() {
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

function openshift_login () {
  if [[ -z $KUBECONFIG ]] && [[ ! -s $HOME/.kube/config ]]; then
    log "KUBECONFIG var is not defined and cannot find kube config in the home directory, trying to use oc login"
    if [[ -n ${KUBEUSER}} ]] && [[ -n ${KUBEPASSWORD} ]] && [[ -n ${KUBEURL} ]]; then
  	  oc login -u ${KUBEUSER} -p ${KUBEPASSWORD} ${KUBEURL}
    else
  	  log "No openshift authentication method found, exiting"
         exit 1
    fi
  fi
}


# Two arguments are 'pod label' and 'timeout in seconds'
function get_pod () {
  counter=0
  sleep_time=5
  counter_max=$(( $2 / sleep_time ))
  pod_name="False"
  until [ $pod_name != "False" ] ; do
    sleep $sleep_time
    pod_name=$(oc get pods -l $1 --namespace ${3:-benchmark-operator} -o name | cut -d/ -f2)
    if [ -z $pod_name ]; then
      pod_name="False"
    fi
    counter=$(( counter+1 ))
    if [ $counter -eq $counter_max ]; then
      echo "Unable to locate the pod!"
      return 1
    fi
  done
  echo $pod_name
  return 0
}

# The argument is 'timeout in seconds'
function get_uuid () {
  sleep_time=$1
  sleep $sleep_time
  counter=0
  counter_max=6
  uuid="False"
  until [ $uuid != "False" ] ; do
    uuid=$(oc -n benchmark-operator get benchmarks -o jsonpath='{.items[0].status.uuid}')
    if [ -z $uuid ]; then
      sleep $sleep_time
      uuid="False"
    fi
    counter=$(( counter+1 ))
    if [ $counter -eq $counter_max ]; then
      echo "Unable to fetch the benchmark uuid!"
      return 1
    fi
  done
  echo $uuid
  return 0
}

# The argument is 'timeout and 'pod name' in seconds'
function check_pod_ready_state () {
  pod_name=$1
  timeout=$2
  echo "Waiting $timeout for $pod_name pod to transition to the ready state..."
  oc wait --for=condition=ready pods --namespace ${3:-benchmark-operator} $pod_name --timeout=$timeout
  return $?
}




gen_spreadsheet_helper() {
  pip install oauth2client>=4.1.3 gspread
  python3 $(dirname $(realpath ${BASH_SOURCE[0]}))/csv_gen.py --sheetname ${1}-$(date "+%Y-%m-%dT%H:%M:%S") -c ${2} --email ${3} --service-account ${4}
}

##############################################################################
# Imports a CSV file into a google spreadsheet
# Arguments:
#   Spreadsheet name
#   CSV file to import
#   Gmail email address
#   Service account file
##############################################################################
gen_spreadsheet() {
  log "Installing requirements to generate spreadsheet"
  if [[ "${VIRTUAL_ENV}" != "" ]]; then
    gen_spreadsheet_helper ${1} ${2} ${3} ${4}
  else
    csv_tmp=$(mktemp -d)
    python -m venv ${csv_tmp}
    source ${csv_tmp}/bin/activate
    gen_spreadsheet_helper ${1} ${2} ${3} ${4}
    deactivate
    rm -rf ${csv_tmp}
  fi
}



##############################################################################
# Creates a new document containing cluster information
# Arguments:
#   Benchmark name (as `oc get benchmark` displays it
#   start_date (epoch)
#   end_date (epoch)
##############################################################################
gen_metadata() {
  local BENCHMARK=$1
  local START_DATE=$2
  local END_DATE=$3

  # construct all the required information
  local VERSION_INFO=$(oc version -o json)
  local INFRA_INFO=$(oc get infrastructure.config.openshift.io cluster -o json)
  local PLATFORM=$(echo ${INFRA_INFO} | jq -r .spec.platformSpec.type)
  if [[ ${PLATFORM} =~ "AWS" ]]; then
    local CLUSTERTYPE=$(echo ${INFRA_INFO} | jq -r .status.platformStatus.aws.resourceTags[0].value)
  fi
  local CLUSTER_NAME=$(echo ${INFRA_INFO} | jq -r .status.infrastructureName)
  local OCP_VERSION=$(echo ${VERSION_INFO} | jq -r .openshiftVersion)
  local K8S_VERSION=$(echo ${VERSION_INFO} | jq -r .serverVersion.gitVersion)
  local MASTER_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/master= --no-headers | wc -l)
  local WORKER_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/worker= --no-headers | wc -l)
  local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/workload= --no-headers --ignore-not-found | wc -l)
  local INFRA_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found | wc -l)
  local SDN_TYPE=$(oc get networks.operator.openshift.io cluster -o jsonpath="{.spec.defaultNetwork.type}")
  if [[ ${PLATFORM} != "BareMetal" ]]; then
    local MASTER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/master= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
    local WORKER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/worker= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
    if [[ ${WORKLOAD_NODES_COUNT} -gt 0 ]]; then
      local WORKLOAD_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/workload= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
    fi
    if [[ ${INFRA_NODES_COUNT} -gt 0 ]]; then
      local INFRA_NODES_TYPE=$(oc get node --ignore-not-found -l node-role.kubernetes.io/infra= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
    fi
  fi
  if [[ ${BENCHMARK} =~ "cyclictest" ]]; then
    local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/cyclictest= --no-headers --ignore-not-found | wc -l)
  elif [[ $BENCHMARK =~ "oslat" ]]; then
    local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/oslat= --no-headers --ignore-not-found | wc -l)
  elif [[ $BENCHMARK =~ "testpmd" ]]; then
    local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/testpmd= --no-headers --ignore-not-found | wc -l)
  else
    local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/workload= --no-headers --ignore-not-found | wc -l)
  fi
  local TOTAL_NODES=$(oc get node --no-headers | wc -l)
  local RESULT=$(oc get benchmark ${BENCHMARK} -o json | jq -r '.status.state')
  local UUID=$(oc get benchmark ${BENCHMARK} -o json | jq -r '.status.uuid')


# stupid indentation because bash won't find the closing EOF if it's not at the beginning of the line
local METADATA=$(cat << EOF
{
"uuid":"${UUID}",
"platform":"${PLATFORM}",
"clustertype":"${CLUSTERTYPE}",
"ocp_version":"${OCP_VERSION}",
"k8s_version":"${K8S_VERSION}",
"master_nodes_type":"${MASTER_NODES_TYPE}",
"worker_nodes_type":"${WORKER_NODES_TYPE}",
"infra_nodes_type":"${INFRA_NODES_TYPE}",
"workload_nodes_type":"${INFRA_NODES_TYPE}",
"master_nodes_count":${MASTER_NODES_COUNT},
"worker_nodes_count":${WORKER_NODES_COUNT},
"infra_nodes_count":${INFRA_NODES_COUNT},
"workload_nodes_count":${WORKLOAD_NODES_COUNT},
"total_nodes":${TOTAL_NODES},
"sdn_type":"${SDN_TYPE}",
"benchmark":"${BENCHMARK}",
"timestamp":"${START_DATE}",
"end_date":"${END_DATE}",
"result":"${RESULT}"
}
EOF
)

  # send the document to ES
  log "Indexing benchmark metadata to ${ES_SERVER}/${ES_INDEX}"
  curl -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${ES_INDEX}/_doc -d "${METADATA}"
}


