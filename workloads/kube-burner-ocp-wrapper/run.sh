#!/bin/bash -e

set -e
set +o histexpand

ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.6}
CHURN=${CHURN:-true}
WORKLOAD=${WORKLOAD:?}
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=$(uuidgen)
KUBE_DIR=${KUBE_DIR:-/tmp}

download_binary(){
  KUBE_BURNER_URL=https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-${KUBE_BURNER_VERSION}-Linux-x86_64.tar.gz
  curl -sS -L ${KUBE_BURNER_URL} | tar -xzC ${KUBE_DIR}/ kube-burner
}

get_worker_nodes() {
  local PROMETHEUS_ENDPOINT="$1"
  local PROMETHEUS_TOKEN="$2"
  
  # Retrieve worker nodes
  response=$(curl -H "Authorization: Bearer ${PROMETHEUS_TOKEN}" -k --silent --globoff "${PROMETHEUS_ENDPOINT}/api/v1/query?query=sum(kube_node_role{role!~'master|infra|obo|control-plane|workload'})by(node)&time=$(date +%s)")
  
  # Extract the worker names
  nodes=$(echo "${response}" | jq -r '.data.result[].metric.node')
  
  # Concatenate the node names
  if [[ -n ${nodes} ]]; then
    echo "${nodes}" | tr '\n' '|'
  fi
}

hypershift(){
  echo "HyperShift detected"
  # Get hosted cluster ID and name
  HC_ID=$(oc get infrastructure cluster -o go-template --template='{{.status.infrastructureName}}')
  HC_NAME=$(oc get infrastructure cluster -o go-template --template='{{range .status.platformStatus.aws.resourceTags}}{{if eq .key "api.openshift.com/name" }}{{.value}}{{end}}{{end}}')
  
  if [[ -z ${HC_ID} ]] || [[ -z ${HC_NAME} ]]; then
    echo "Couldn't obtain hosted cluster id and/or hosted cluster name"
    echo -e "HC_ID: ${HC_ID}\nHC_NAME: ${HC_NAME}"
    exit 1
  fi
  
  # Hosted control-plane namespace is composed by the cluster ID plus the cluster name
  HCP_NAMESPACE=${HC_ID}-${HC_NAME}
  
  echo "Creating OBO route"
  oc --kubeconfig=${MC_KUBECONFIG} apply -f obo-route.yml
  echo "Fetching OBO endpoint"
  MC_OBO=http://$(oc --kubeconfig=${MC_KUBECONFIG} get route -n openshift-observability-operator prometheus-hypershift -o jsonpath="{.spec.host}")
  MC_PROMETHEUS=https://$(oc --kubeconfig=${MC_KUBECONFIG} get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  MC_PROMETHEUS_TOKEN=$(oc --kubeconfig=${MC_KUBECONFIG} sa new-token -n openshift-monitoring prometheus-k8s)
  SC_PROMETHEUS=https://$(oc --kubeconfig=${SC_KUBECONFIG} get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  SC_PROMETHEUS_TOKEN=$(oc --kubeconfig=${SC_KUBECONFIG} sa new-token -n openshift-monitoring prometheus-k8s)
  HOSTED_PROMETHEUS=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  HOSTED_PROMETHEUS_TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)

  echo "Get all the management worker nodes, excludes infra, obo, workload"
  MGMT_WORKER_NODES=$(get_worker_nodes "${MC_PROMETHEUS}" "${MC_PROMETHEUS_TOKEN}")

  echo "Get all the service worker nodes, excludes infra, obo, workload"
  SVC_WORKER_NODES=$(get_worker_nodes "${SC_PROMETHEUS}" "${SC_PROMETHEUS_TOKEN}")
    
  echo "Exporting required vars"
  cat << EOF
MC_OBO: ${MC_OBO}
MC_PROMETHEUS: ${MC_PROMETHEUS}
MC_PROMETHEUS_TOKEN: <truncated>
HOSTED_PROMETHEUS: ${HOSTED_PROMETHEUS}
HOSTED_PROMETHEUS_TOKEN: <truncated>
HCP_NAMESPACE: ${HCP_NAMESPACE}
MGMT_WORKER_NODES: ${MGMT_WORKER_NODES}
SC_PROMETHEUS: ${SC_PROMETHEUS}
SC_PROMETHEUS_TOKEN: <truncated>
SVC_WORKER_NODES: ${SVC_WORKER_NODES}

EOF
  echo "Indexing Management & Service cluster stats before executing"
  METADATA=$(cat << EOF
{
"uuid": "${UUID}",
"mgmtClusterName": "$(oc get --kubeconfig=${MC_KUBECONFIG} infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"hostedClusterName": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"timestamp": "$(date +%s%3N)"
}
EOF
  )
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/ripsaw-kube-burner/_doc -d "${METADATA}" -o /dev/null
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES SC_PROMETHEUS SC_PROMETHEUS_TOKEN SVC_WORKER_NODES
}

download_binary
cmd="${KUBE_DIR}/kube-burner ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
if [[ ${WORKLOAD} =~ "cluster-density" ]]; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi

if [[ -n ${MC_KUBECONFIG} ]] && [[ -n ${ES_SERVER} ]] && -n ${SC_KUBECONFIG}; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
  hypershift
fi
# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
fi
cmd+=" ${EXTRA_FLAGS}"

echo $cmd
exec $cmd
