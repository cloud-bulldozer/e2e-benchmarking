#!/bin/bash -e

set -e

ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
LOG_LEVEL=${LOG_LEVEL:-info}
KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.5}
CHURN=${CHURN:-true}
WORKLOAD=${WORKLOAD:?}
QPS=${QPS:-20}
BURST=${BURST:-20}
GC=${GC:-true}
EXTRA_FLAGS=${EXTRA_FLAGS:-}

download_binary(){
  KUBE_BURNER_URL=https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-${KUBE_BURNER_VERSION}-Linux-x86_64.tar.gz
  curl -sS -L ${KUBE_BURNER_URL} | tar -xzC /tmp/ kube-burner
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
  HOSTED_PROMETHEUS=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
  HOSTED_PROMETHEUS_TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)
  echo "Exporting required vars"
  cat << EOF
MC_OBO: ${MC_OBO}
MC_PROMETHEUS: ${MC_PROMETHEUS}
MC_PROMETHEUS_TOKEN: <truncated>
HOSTED_PROMETHEUS: ${HOSTED_PROMETHEUS}
HOSTED_PROMETHEUS_TOKEN: <truncated>
HCP_NAMESPACE: ${HCP_NAMESPACE}

EOF
  export MC_OBO MC_PROMETHEUS MC_PROMETHEUS_TOKEN HOSTED_PROMETHEUS HOSTED_PROMETHEUS_TOKEN HCP_NAMESPACE
}

download_binary
cmd="/tmp/kube-burner ocp ${WORKLOAD} --log-level=${LOG_LEVEL} --qps=${QPS} --burst=${BURST} --gc=${GC}"
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
echo $cmd
exec $cmd
