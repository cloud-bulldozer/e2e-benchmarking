#!/bin/bash -e

set -e
source ./egressip.sh

ES_SERVER=${ES_SERVER=https://USER:PASSWORD@HOSTNAME:443}
LOG_LEVEL=${LOG_LEVEL:-info}
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.8.0}
OS=$(uname -s)
HARDWARE=$(uname -m)
PERFORMANCE_PROFILE=${PERFORMANCE_PROFILE:-default}
CHURN=${CHURN:-true}
WORKLOAD=${WORKLOAD:?}
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
UUID=${UUID:-$(uuidgen)}
KUBE_DIR=${KUBE_DIR:-/tmp}
US_WEST_2A=${US_WEST_2A:-}
US_WEST_2B=${US_WEST_2B:-}
US_WEST_2C=${US_WEST_2C:-}
US_WEST_2D=${US_WEST_2D:-}

download_binary(){
  KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-${OS}-${HARDWARE}.tar.gz"
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
    QUERY="sum(cluster:nodes_roles{label_hypershift_openshift_io_control_plane=\"true\",label_hypershift_openshift_io_request_serving_component!=\"true\"})by(node)"

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
  PPROF=false # pporf is not supported for index job, it is not required for index executions.
else
  cmd="${KUBE_DIR}/kube-burner-ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
fi
cmd+=" ${EXTRA_FLAGS}"
if [[ ${WORKLOAD} =~ "cluster-density" || ${WORKLOAD} =~ "udn-density-pods" || ${WORKLOAD} =~ "rds-core" ]] && [[ ! ${WORKLOAD} =~ "web-burner" ]] ; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ ${WORKLOAD} =~ "kube-burner-ai" ]]; then
  WORKLOAD="cluster-density"
  numbers=(100 150 200 250 300 350 400 450 500)
  array_length=${#numbers[@]}
  random_index=$(( $RANDOM % array_length ))
  ITERATIONS=${numbers[$random_index]}

  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ ${WORKLOAD} =~ ^(crd-scale|pvc-density|olm|udn-bgp)$ ]]; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS}"
fi
if [[ ${WORKLOAD} =~ "egressip" ]]; then
  prep_aws
  get_egressip_external_server
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --external-server-ip=${EGRESSIP_EXTERNAL_SERVER_IP}"
fi

# if ES_SERVER is specified and for hypershift clusters
if [[ -n ${MC_KUBECONFIG} ]] && [[ -n ${ES_SERVER} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
  hypershift
  curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/ripsaw-kube-burner/_doc -d "${METADATA}" -o /dev/null
# for non-hypershift cluster
elif [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
else
  echo "ES_SERVER is not set, not indexing the results"
fi
# If PERFORMANCE_PROFILE is specified
if [[ -n ${PERFORMANCE_PROFILE} && ${WORKLOAD} =~ "rds-core" ]]; then
  cmd+=" --perf-profile=${PERFORMANCE_PROFILE}"
fi

# Capture the exit code of the run, but don't exit the script if it fails.
set +e

# scale machineset
for machineset_name in $(oc get -n openshift-machine-api machineset --no-headers -o custom-columns=":.metadata.name" | grep -i worker); do
  region=$(oc get -n openshift-machine-api machineset --no-headers -o custom-columns=":.spec.template.spec.providerSpec.value.placement.availabilityZone" $machineset_name)
  # region will be of the form us-west-2a. We need to match it to user provided var i.e replae "-" with '_' and then convert it to upper case.
  # For example us-west-2a will be converted to US_WEST_2A.
  region_var=$(echo "$region" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  # desired_replicas will be the value stored in US_WEST_2A (if povided by user)
  desired_replicas=${!region_var}
  if [[ "${desired_replicas}" != "" ]]; then
    echo "scale the ${machineset_name} to ${desired_replicas}"
    current_replicas=$(oc get -n openshift-machine-api -o template machineset "$machineset_name" --template={{.status.replicas}})
    # scale 50 at at time
    while ((current_replicas < desired_replicas)); do
      needed_replicas=$((desired_replicas - current_replicas))
      scale_step=$((current_replicas + needed_replicas))

      if ((needed_replicas > 50)); then
        scale_step=$((current_replicas + 50))
      fi
      echo "Scaling from $current_replicas to $scale_step replicas."
      oc scale -n openshift-machine-api machineset "$machineset_name" --replicas="${scale_step}"
      # wait for 1 hour i.e 720 retries, each retry with 5 seconds sleep
      for ((i = 1; i <= 720; i++)); do
        available_replicas=$(oc get -n openshift-machine-api -o template machineset "$machineset_name" --template={{.status.availableReplicas}})
        if [ "$available_replicas" -eq "$scale_step" ]; then
          echo "Desired number of replicas ($scale_step) reached."
          break
        fi
        sleep 5
      done
      current_replicas=$(oc get -n openshift-machine-api -o template machineset "$machineset_name" --template={{.status.replicas}})
    done
  fi
done


# Label workers with ovnic. Metrics from only these workers are pulled.
# node-desnity-cni on 500 nodes runs for 2 hours 15 minutes. Scraping metrics from 500 nodes for the duration of 2 hours 15 minutes is overkill.
# So we scrape from only 10 worker nodes if the worker node count is more than 120.
workers_to_label=$(oc get nodes --ignore-not-found -l node-role.kubernetes.io/worker --no-headers=true | wc -l) || true
if [ "$workers_to_label" -gt 2 ]; then
  workers_to_label=2
fi

count=0
for node in $(oc get nodes --ignore-not-found -l node-role.kubernetes.io/worker --no-headers -o custom-columns=":.metadata.name"); do
  if [ "$count" -eq "$workers_to_label" ]; then
    break
  fi
  oc label nodes $node 'node-role.kubernetes.io/ovnic='
  ((count++))
done


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

if [[ ${WORKLOAD} =~ "egressip" ]]; then
    cleanup_egressip_external_server
fi
exit $exit_code
