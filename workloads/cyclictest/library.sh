#!/bin/bash

gen_metadata() {
	# construct all the required information
	local VERSION_INFO=$(oc version -o json)
	local INFRA_INFO=$(oc get infrastructure.config.openshift.io cluster -o json)
	local PLATFORM=$(echo ${INFRA_INFO} | jq -r .spec.platformSpec.type)
	local CLUSTER_NAME=$(echo ${INFRA_INFO} | jq -r .status.infrastructureName)
	local OCP_VERSION=$(echo ${VERSION_INFO} | jq -r .openshiftVersion)
	local K8S_VERSION=$(echo ${VERSION_INFO} | jq -r .serverVersion.gitVersion)
	local MASTER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/master= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}') # no values for BM deployments
	local MASTER_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/master= --no-headers | wc -l)
	local WORKER_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/worker= --no-headers | wc -l)
	local WORKER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/worker= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	local INFRA_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found | wc -l)
	local WORKLOAD_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/workload= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	local WORKLOAD_NODES_COUNT=$(oc get node -l node-role.kubernetes.io/workload= --no-headers --ignore-not-found | wc -l)
	local SDN_TPYE=$(oc get networks.operator.openshift.io cluster -o jsonpath="{.spec.defaultNetwork.type}")
	if [[ ${PLATFORM} != "BareMetal" ]]; then
	  local MASTER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/master= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	  local WORKLOAD_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/workload= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	  local WORKER_NODES_TYPE=$(oc get node -l node-role.kubernetes.io/worker= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	  if [[ ${INFRA_NODES} -gt 0 ]]; then
	    local INFRA_NODES_TYPE=$(oc get node --ignore-not-found -l node-role.kubernetes.io/infra= --no-headers -o go-template='{{index (index .items 0).metadata.labels "beta.kubernetes.io/instance-type"}}')
	  fi
	fi
        local TOTAL_NODES=$(oc get node --no-headers | wc -l)

# stupid indentation because bash won't find the closing EOF if it's not at the beginning of the line

local METADATA=$(cat << EOF
{{{}}
  "uuid": "${uuid}",
  "platform": "${PLATFORM}",
  "ocp_version": "${OCP_VERSION}",
  "k8s_version": "${K8S_VERSION}",
  "master_nodes_type": "${MASTER_NODES_TYPE}",
  "worker_nodes_type": "${WORKER_NODES_TYPE}",
  "infra_nodes_type": "${INFRA_NODES_TYPE}",
  "workload_nodes_type": "${INFRA_NODES_TYPE}",
  "master_nodes_count": ${MASTER_NODES_COUNT},
  "worker_nodes_count": ${WORKER_NODES_COUNT},
  "infra_nodes_count": ${INFRA_NODES_COUNT},
  "workload_nodes_count": ${INFRA_NODES_COUNT},
  "total_nodes": "${TOTAL_NODES}",
  "sdn_type": "${SDN_TYPE}",
  "benchmark": "${1}",
  "result": "${2}"
  "start_date": "${3}",
  "end_date": "${3}",
}
EOF
)
echo $METADATA
}

gen_metadata
