source env.sh
source ../../utils/common.sh

openshift_login

export UUID=${UUID:-$(uuidgen)}
export PROM_URL=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
export PROM_TOKEN=$(oc create token -n openshift-monitoring prometheus-k8s --duration=6h || oc sa get-token -n openshift-monitoring prometheus-k8s || oc sa new-token -n openshift-monitoring prometheus-k8s)

log(){
  echo -e "\033[1m$(date -u) ${@}\033[0m"
}

get_number_of_pods(){
  POD_REPLICAS=0
  if [[ -n ${PODS_PER_NODE} ]]; then
    local NUMBER_OF_NODES=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= --no-headers | wc -l)
    POD_REPLICAS=$((NUMBER_OF_NODES * PODS_PER_NODE))
  else
    log "Calculating number of pods required to fill all worker nodes"
    for n in $(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= -o jsonpath="{.items[*].metadata.name}"); do
       local pods_in_node=$(oc get pod -A --field-selector=spec.nodeName=${n} | grep -cw Running)
       let POD_REPLICAS=${POD_REPLICAS}+249-${pods_in_node}
    done
    if [[ ${POD_REPLICAS} -le 0 ]]; then
      log "Wrong number of pods: ${POD_REPLICAS}"
      exit
    fi
  fi
  log "Pods to deploy across worker nodes: ${POD_REPLICAS}"
}

get_pods_per_namespace(){
  export PODS_PER_NS=$((POD_REPLICAS / NUMBER_OF_NS))
  log "We'll create ${NUMBER_OF_NS} namespaces with ${PODS_PER_NS} pods each"
}

# Receives the kube-burner configuration file as parameter
run_test(){
  log "Running kube-burner using config ${1} and metrics ${METRICS}"
  export POD_REPLICAS

  if [ ${KUBE_BURNER_RELEASE_URL} == "latest" ] ; then
    KUBE_BURNER_RELEASE_URL=$(curl -s https://api.github.com/repos/cloud-bulldozer/kube-burner/releases/latest | jq -r '.assets | map(select(.name | test("linux-x86_64"))) | .[0].browser_download_url')
  fi
  curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz
  ./kube-burner init -c ${1} --uuid=${UUID} -u=${PROM_URL} --token=${PROM_TOKEN} -m="${METRICS}"
  if [[ ${CLEANUP_WHEN_FINISH} == "true" ]]; then
    log "Cleaning up benchmark stuff"
    kube-burner destroy --uuid ${UUID}
  fi
}
