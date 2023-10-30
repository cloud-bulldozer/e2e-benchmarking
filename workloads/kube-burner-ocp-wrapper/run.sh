#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.7.8}
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
  KUBE_BURNER_URL=https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz
  curl -sS -L ${KUBE_BURNER_URL} | tar -xzC ${KUBE_DIR}/ kube-burner
}

hypershift(){
  echo "HyperShift detected"
  echo "Indexing Management cluster stats before executing"
  METADATA=$(cat << EOF
{
"uuid" : "${UUID}",
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
    export elapsed=20m
  fi
  
  echo "Indexing Management cluster stats before executing"
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
}

download_binary
if [[ ${WORKLOAD} =~ "index" ]]; then
  cmd="${KUBE_DIR}/kube-burner index --uuid=${UUID} --start=$START_TIME --end=$((END_TIME+600)) --log-level ${LOG_LEVEL}"
else
  cmd="${KUBE_DIR}/kube-burner ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
  cmd+=" ${EXTRA_FLAGS}"
fi
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
JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
$cmd
exit_code=$?
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi
env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" ../../utils/index.sh
exit $exit_code
