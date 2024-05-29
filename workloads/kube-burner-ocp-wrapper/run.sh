#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.2.5}
CHURN=${CHURN:-true}
WORKLOAD=${WORKLOAD:?}
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=${UUID:-$(uuidgen)}
KUBE_DIR=${KUBE_DIR:-/tmp}

download_binary(){
  KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz"
  curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
}

hypershift(){
  echo "HyperShift detected"
  echo "Indexing Management cluster stats before executing"
  METADATA=$(cat << EOF
{
"uuid": "${UUID}",
"workload": "${WORKLOAD}",
"mgmtClusterName": "$(oc get --kubeconfig=${MC_KUBECONFIG} infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"hostedClusterName": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
"timestamp": "$(date +%s%3N)"
}
EOF
)
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/ripsaw-kube-burner/_doc -d "${METADATA}" -o /dev/null
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
  HOSTED_PROMETHEUS=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  HOSTED_PROMETHEUS_TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)

  echo "Get all management worker nodes, excludes infra, obo, workload"
  Q_NODES=""
  for n in $(curl -H "Authorization: Bearer ${MC_PROMETHEUS_TOKEN}" -k --silent --globoff  ${MC_PROMETHEUS}/api/v1/query?query='sum(cluster:nodes_roles{label_hypershift_openshift_io_control_plane="true"})by(node)&time='$(date +"%s")'' | jq -r '.data.result[].metric.node'); do
    if [[ ${Q_NODES} == "" ]]; then
      Q_NODES=${n}
    else
      Q_NODES=${Q_NODES}"|"${n};
    fi
  done
  MGMT_WORKER_NODES=${Q_NODES}
    
  echo "Exporting required vars"
  cat << EOF
MC_OBO: ${MC_OBO}
MC_PROMETHEUS: ${MC_PROMETHEUS}
MC_PROMETHEUS_TOKEN: <truncated>
HOSTED_PROMETHEUS: ${HOSTED_PROMETHEUS}
HOSTED_PROMETHEUS_TOKEN: <truncated>
HCP_NAMESPACE: ${HCP_NAMESPACE}
MGMT_WORKER_NODES: ${MGMT_WORKER_NODES}
EOF

  if [[ ${WORKLOAD} =~ "index" ]]; then
    export elapsed=${ELAPSED:-20m}
  fi
  
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES
}

download_binary
if [[ ${WORKLOAD} =~ "index" ]]; then
  cmd="${KUBE_DIR}/kube-burner-ocp index --uuid=${UUID} --start=$START_TIME --end=$((END_TIME+600)) --log-level ${LOG_LEVEL}"
  JOB_START=$(date -u -d "@$START_TIME" +"%Y-%m-%dT%H:%M:%SZ")
  JOB_END=$(date -u -d "@$((END_TIME + 600))" +"%Y-%m-%dT%H:%M:%SZ")
else
  cmd="${KUBE_DIR}/kube-burner-ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
fi
cmd+=" ${EXTRA_FLAGS}"
if [[ ${WORKLOAD} =~ "cluster-density" ]]; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ -n ${MC_KUBECONFIG} ]] && [[ -n ${ES_SERVER} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
  hypershift
fi
# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
fi
# Capture the exit code of the run, but don't exit the script if it fails.
set +e

echo $cmd
JOB_START=${JOB_START:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
$cmd
exit_code=$?
JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" ../../utils/index.sh
exit $exit_code
