#!/bin/bash -e

# Dev presets
CHURN=${CHURN:-false}
WORKLOAD=${WORKLOAD:-cluster-density-v2}
ITERATIONS=${ITERATIONS:-2}

echo "RUNNING DEV BRANCH"
pwd

set +e
set -x

source ./egressip.sh

ES_SERVER=${ES_SERVER=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.3.2}
CHURN=${CHURN:-true}
WORKLOAD=${WORKLOAD:?}
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=${UUID:-$(uuidgen)}
KUBE_DIR=${KUBE_DIR:-/tmp}

download_binary(){
  if uname | grep -i darwin; then
    KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-darwin-arm64.tar.gz"
  else
    KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz"
  fi
  curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
}

hypershift(){
  echo "HyperShift detected"

  # Get hosted cluster ID and name
  HC_ID=$(oc get infrastructure cluster -o go-template --template='{{.status.infrastructureName}}')
  HC_PLATFORM=$(oc get infrastructure cluster -o go-template --template='{{.status.platform}}'| awk '{print tolower($0)}')

  if [[ $HC_PLATFORM == "aws" ]]; then
    echo "Detected ${HC_PLATFORM} environment..."

    MC_NAME=$(oc get --kubeconfig=${MC_KUBECONFIG} infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)
    HC_NAME=$(oc get infrastructure cluster -o go-template --template='{{range .status.platformStatus.aws.resourceTags}}{{if eq .key "api.openshift.com/name" }}{{.value}}{{end}}{{end}}')
    # Hosted control-plane namespace is composed by the cluster ID plus the cluster name
    HCP_NAMESPACE=${HC_ID}-${HC_NAME}
    QUERY="sum(cluster:nodes_roles{label_hypershift_openshift_io_control_plane=\"true\"})by(node)"

    echo "Creating OBO route on MC"
    oc --kubeconfig=${MC_KUBECONFIG} apply -f obo-route.yml
    echo "Fetching OBO endpoint"
    MC_OBO=http://$(oc --kubeconfig=${MC_KUBECONFIG} get route -n openshift-observability-operator prometheus-hypershift -o jsonpath="{.spec.host}")
    MC_PROMETHEUS=https://$(oc --kubeconfig=${MC_KUBECONFIG} get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
    MC_PROMETHEUS_TOKEN=$(oc --kubeconfig=${MC_KUBECONFIG} sa new-token -n openshift-monitoring prometheus-k8s)
    HC_PRODUCT="rosa"
  else
    echo "Detected ${HC_PLATFORM} environment..."

    MC_NAME=$(kubectl config view -o jsonpath='{.clusters[].name}' --kubeconfig=${MC_KUBECONFIG})
    HC_NAME=$(oc get infrastructure cluster -o go-template --template='{{.status.etcdDiscoveryDomain}}' | awk -F. '{print$1}')
    HCP_NAMESPACE=${HC_NAME}
    QUERY="sum(kube_node_role{cluster=\"$MC_NAME\",role=\"worker\"})by(node)"

    if [[ -z ${AKS_PROM} ]] || [[ -z ${AZURE_PROM} ]] ; then
      echo "Azure/AKS prometheus inputs are missing, exiting.."
      exit 1
    elif [[ -z ${AZURE_PROM_TOKEN} ]]; then
      if [[ -z ${AZ_CLIENT_SECRET} ]] || [[ -z ${AZ_CLIENT_ID} ]] ; then
        echo "Azure/AKS prometheus token is missing and cannot be calculated, exiting.."
	exit 1
      else
	AZURE_PROM_TOKEN=$(curl --request POST 'https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/oauth2/v2.0/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "client_id=${AZ_CLIENT_ID}" --data-urlencode 'grant_type=client_credentials' --data-urlencode "client_secret=${AZ_CLIENT_SECRET}" --data-urlencode 'scope=https://prometheus.monitor.azure.com/.default' | jq -r '.access_token')
      fi
    fi

    MC_OBO=$AKS_PROM
    MC_PROMETHEUS=$AZURE_PROM
    MC_PROMETHEUS_TOKEN=$AZURE_PROM_TOKEN
    HC_PRODUCT="aro"
  fi

  echo "Indexing Management cluster stats"
  METADATA=$(cat << EOF
{
"uuid": "${UUID}",
"workload": "${WORKLOAD}",
"mgmtClusterName": "${MC_NAME}",
"hostedClusterName": "${HC_NAME}",
"timestamp": "$(date +%s%3N)"
}
EOF
)
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/ripsaw-kube-burner/_doc -d "${METADATA}" -o /dev/null

  HOSTED_PROMETHEUS=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  HOSTED_PROMETHEUS_TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)

  echo "Get all management worker nodes, excludes infra, obo, workload"
  Q_NODES=""
  Q_STDOUT=$(curl -H "Authorization: Bearer ${MC_PROMETHEUS_TOKEN}" -k --silent --globoff  ${MC_PROMETHEUS}/api/v1/query?query=${QUERY}&time='$(date +"%s")')
  for n in $(echo $Q_STDOUT | jq -r '.data.result[].metric.node'); do
    if [[ ${Q_NODES} == "" ]]; then
      Q_NODES=${n}
    else
      Q_NODES=${Q_NODES}"|"${n};
    fi
  done
  MGMT_WORKER_NODES=${Q_NODES}

  echo "Exporting required vars"
  cat << EOF
MC_NAME: ${MC_NAME}
MC_OBO: ${MC_OBO}
MC_PROMETHEUS: ${MC_PROMETHEUS}
MC_PROMETHEUS_TOKEN: <truncated>
HOSTED_PROMETHEUS: ${HOSTED_PROMETHEUS}
HOSTED_PROMETHEUS_TOKEN: <truncated>
HCP_NAMESPACE: ${HCP_NAMESPACE}
MGMT_WORKER_NODES: ${MGMT_WORKER_NODES}
HC_PRODUCT: ${HC_PRODUCT}
EOF

  if [[ ${WORKLOAD} =~ "index" ]]; then
    export elapsed=${ELAPSED:-20m}
  fi
  
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES HC_PRODUCT MC_NAME

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
if [[ ${WORKLOAD} =~ "cluster-density" ]] && [[ ! ${WORKLOAD} =~ "web-burner" ]] ; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ ${WORKLOAD} =~ "egressip" ]]; then
  prep_aws
  get_egressip_external_server
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --external-server-ip=${EGRESSIP_EXTERNAL_SERVER_IP}"
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

## We could download the metrics config from the stackrox repo.
#curl -LsSo stackrox.yml https://raw.githubusercontent.com/stackrox/stackrox/master/tests/performance/scale/tests/kube-burner/cluster-density/metrics.yml
#
## Get the configuration kube-burner will run.
#$cmd --extract
#ls -latr *.yml
## Modify the configuration to reference additional local metrics files.
#sed -i '' -e 's/\[{{.METRICS}}\]/\[stackrox.yml,{{.METRICS}}\]/' *.yml
#grep METRICS *.yml
export CLUSTER_PROM_URL="https://$(oc -n openshift-monitoring get routes prometheus-k8s --no-headers | awk '{print $2}')"
echo "TOKEN:[${TOKEN}]"
export TOKEN=${TOKEN:-"$(oc create token -n openshift-monitoring prometheus-k8s)"}
echo "TOKEN:[${TOKEN}]"

echo $cmd
JOB_START=${JOB_START:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
$cmd
exit_code=$?

$cmd <(echo -e "- endpoint: $(oc -n openshift-monitoring get routes prometheus-k8s --no-headers|awk "{print \$2}")"'\n  token: '"$(oc create token -n openshift-monitoring prometheus-k8s)"'\n  metrics: [{{.EXTRA_METRICS_FILE}}]\n  indexer:\n    esServers: ["{{.ES_SERVER}}"]\n    defaultIndex: {{.ES_INDEX}}')

JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" ../../utils/index.sh

if [[ ${WORKLOAD} =~ "egressip" ]]; then
    cleanup_egressip_external_server
fi
exit $exit_code
