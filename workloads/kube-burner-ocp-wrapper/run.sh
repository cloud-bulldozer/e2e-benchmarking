#!/bin/bash -e

set -e

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

check_managed_cluster() {
   status=$(oc get infrastructure/cluster -o=jsonpath='{.status.platformStatus.*.resourceTags[0]}')
   if [[ $status =~ managed ]]; then
      echo "Detected a Managed Cluster"
      managed=true
   fi
}

remove_managed_webhook_validation() {
   echo "Disabling validation-webhook for Managed cluster"
   oc patch -n openshift-validation-webhook daemonset validation-webhook -p '{"spec": {"template": {"spec": {"nodeSelector": {"non-existing": "true"}}}}}'
   
}

add_managed_webhook_validation() {
    echo "Enabling validation-webhook for Managed cluster"
    oc patch -n openshift-validation-webhook daemonset validation-webhook --type json -p '[{ "op": "remove", "path": "/spec/template/spec/nodeSelector" }]'
}

download_binary(){
  KUBE_BURNER_URL=https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-${KUBE_BURNER_VERSION}-Linux-x86_64.tar.gz
  curl -sS -L ${KUBE_BURNER_URL} | tar -xzC ${KUBE_DIR}/ kube-burner
}

check_managed_cluster

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
  HOSTED_PROMETHEUS=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  HOSTED_PROMETHEUS_TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)

  echo "Get all management worker nodes, excludes infra, obo, workload"
  Q_NODES=""
  for n in $(curl -H "Authorization: Bearer ${MC_PROMETHEUS_TOKEN}" -k --silent --globoff  ${MC_PROMETHEUS}/api/v1/query?query='sum(kube_node_role{role!~"master|infra|workload|obo"})by(node)&time='$(date +"%s")'' | jq -r '.data.result[].metric.node'); do
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
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE MGMT_WORKER_NODES
}

download_binary
cmd="${KUBE_DIR}/kube-burner ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC} --uuid ${UUID}"
if [[ ${WORKLOAD} =~ "cluster-density" ]]; then
  ITERATIONS=${ITERATIONS:?}
  cmd+=" --iterations=${ITERATIONS} --churn=${CHURN}"
fi
if [[ -n ${MC_KUBECONFIG} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
  hypershift
fi
# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=ripsaw-kube-burner"
fi
cmd+=" ${EXTRA_FLAGS}"

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

if [[ $managed == true ]]; then
   remove_managed_webhook_validation
fi

echo $cmd
$cmd

if [[ $managed == true ]]; then
   add_managed_webhook_validation
fi
