ENGINE=${ENGINE:-podman}
INFRA_TEMPLATE=http-perf.yml.tmpl
INFRA_CONFIG=http-perf.yml
KUBE_BURNER_IMAGE=quay.io/cloud-bulldozer/kube-burner:latest
URL_PATH=${URL_PATH:-"/1024.html"}
TERMINATIONS=${TERMINATIONS:-"http edge passthrough reencrypt mix"}
KEEPALIVE_REQUESTS=${KEEPALIVE_REQUESTS:-"1 10 100"}
CLIENTS=${CLIENTS:-"1 40 200"}
SAMPLES=${SAMPLES:-1}
QUIET_PERIOD=${QUIET_PERIOD:-10s}
NUMBER_OF_ROUTERS=${NUMBER_OF_ROUTERS:-2}

export TLS_REUSE=${TLS_REUSE:-true}
export UUID=$(uuidgen)
export RUNTIME=${RUNTIME:-120}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-router-test-results}
export RAMP_UP=${RAMP_UP:-0}
export HOST_NETWORK=${HOST_NETWORK:-true}
export KUBECONFIG=${KUBECONFIG:-~/.kube/config}
export NODE_SELECTOR=${NODE_SELECTOR:-'{"node-role.kubernetes.io/workload": ""}'}
export NUMBER_OF_ROUTES=${NUMBER_OF_ROUTES:-100}
export CERBERUS_URL=${CERBERUS_URL}

log(){
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

deploy_infra(){
  log "Deploying benchmark infrastructure"
  envsubst < ${INFRA_TEMPLATE} > ${INFRA_CONFIG}
  ${ENGINE} run --rm -v $(pwd)/templates:/templates -v ${KUBECONFIG}:/root/.kube/config -v $(pwd)/${INFRA_CONFIG}:/http-perf.yml ${KUBE_BURNER_IMAGE} init -c http-perf.yml --uuid=$(uuidgen)
}

tune_liveness_probe(){
  log "Disabling cluster version and ingress operators"
  kubectl scale --replicas=0 -n openshift-cluster-version deploy/cluster-version-operator
  kubectl scale --replicas=0 -n openshift-ingress-operator deploy/ingress-operator
  log "Increasing ingress controller liveness probe period to $((RUNTIME * 2))s"
  oc set probe -n openshift-ingress --liveness --period-seconds=$((RUNTIME * 2)) deploy/router-default
  log "Scaling number of routers to ${NUMBER_OF_ROUTERS}"
  oc scale --replicas=${NUMBER_OF_ROUTERS} -n openshift-ingress deploy/router-default
  kubectl rollout status -n openshift-ingress deploy/router-default
}


deploy_client(){
  log "Deploying HTTP client resources"
  kubectl create configmap workload --from-file=workload.py
  log "Deploying client"
  envsubst < http-client-resources.yml | kubectl apply -f -
  kubectl rollout status -n http-scale-client deploy/http-scale-client
  client_pod=$(kubectl get pod -l app=http-scale-client -n http-scale-client | grep Running | awk '{print $1}')
}

run_mb(){
  log "Generating configmaps with ${N_CLIENTS} clients ${N_KEEPALIVE_REQUESTS} keep alive requests and path ${URL_PATH}"
  ./gen-mb-config.sh -t ${TLS_REUSE} -c ${N_CLIENTS} -n http-scale-http -p ${URL_PATH} -k ${N_KEEPALIVE_REQUESTS} -s http > mb-http.json
  ./gen-mb-config.sh -t ${TLS_REUSE} -c ${N_CLIENTS} -n http-scale-edge -p ${URL_PATH} -k ${N_KEEPALIVE_REQUESTS} -s https > mb-edge.json
  ./gen-mb-config.sh -t ${TLS_REUSE} -c ${N_CLIENTS} -n http-scale-passthrough -p ${URL_PATH} -k ${N_KEEPALIVE_REQUESTS} -s https > mb-passthrough.json
  ./gen-mb-config.sh -t ${TLS_REUSE} -c ${N_CLIENTS} -n http-scale-reencrypt -p ${URL_PATH} -k ${N_KEEPALIVE_REQUESTS} -s https > mb-reencrypt.json
  jq -s '[.[][]]' *.json > mb-mix.json
  for TERMINATION in ${TERMINATIONS}; do
      log "Copying mb config mb-${TERMINATION}.json to pod ${client_pod}"
      kubectl cp mb-${TERMINATION}.json ${client_pod}:/tmp/mb-${TERMINATION}.json
    for sample in ${SAMPLES}; do
      log "Executing sample ${sample} from termination ${TERMINATION} with ${N_CLIENTS} clients and ${N_KEEPALIVE_REQUESTS} keepalive requests"
      kubectl exec -it ${client_pod} -- python3 /workload/workload.py --mb-config /tmp/mb-${TERMINATION}.json --termination ${TERMINATION} --runtime ${RUNTIME} --ramp-up ${RAMP_UP} --output /tmp/results.csv --sample ${sample} 
      log "Sleeping for ${QUIET_PERIOD} before next test"
      sleep ${QUIET_PERIOD}
    done
  done
}

enable_ingress_opreator(){
  log "Enabling cluster version and ingress operators"
  kubectl scale --replicas=1 -n openshift-cluster-version deploy/cluster-version-operator
  kubectl scale --replicas=1 -n openshift-ingress-operator deploy/ingress-operator
}
