ENGINE=${ENGINE:-podman}
INFRA_TEMPLATE=http-perf.yml.tmpl
INFRA_CONFIG=http-perf.yml
KUBE_BURNER_IMAGE=quay.io/cloud-bulldozer/kube-burner:latest
URL_PATH=${URL_PATH:-"/1024.html"}
TERMINATIONS=${TERMINATIONS:-"http edge passthrough reencrypt mix"}
KEEPALIVE_REQUESTS=${KEEPALIVE_REQUESTS:-"1 10 100"}
CLIENTS=${CLIENTS:-"1 40 200"}
SAMPLES=${SAMPLES:-3}
QUIET_PERIOD=${QUIET_PERIOD:-10s}
THROUGHPUT_TOLERANCE=${THROUGHPUT_TOLERANCE:-5}
LATENCY_TOLERANCE=${LATENCY_TOLERANCE:-5}
PREFIX=${PREFIX:-$(oc get clusterversion version -o jsonpath="{.status.desired.version}")}


export TLS_REUSE=${TLS_REUSE:-true}
export UUID=$(uuidgen)
export RUNTIME=${RUNTIME:-120}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-router-test-results}
export RAMP_UP=${RAMP_UP:-0}
export HOST_NETWORK=${HOST_NETWORK:-true}
export KUBECONFIG=${KUBECONFIG:-~/.kube/config}
export NODE_SELECTOR=${NODE_SELECTOR:-'{node-role.kubernetes.io/workload: }'}
export NUMBER_OF_ROUTES=${NUMBER_OF_ROUTES:-100}
export NUMBER_OF_ROUTERS=${NUMBER_OF_ROUTERS:-2}
export CERBERUS_URL=${CERBERUS_URL}
export SERVICE_TYPE=${SERVICE_TYPE:-NodePort}

log(){
  echo -e "\033[1m$(date "+%d-%m-%YT%H:%M:%S") ${@}\033[0m"
}

deploy_infra(){
  log "Deploying benchmark infrastructure"
  envsubst < ${INFRA_TEMPLATE} > ${INFRA_CONFIG}
  ${ENGINE} run --rm -v $(pwd)/templates:/templates:z -v ${KUBECONFIG}:/root/.kube/config:z -v $(pwd)/${INFRA_CONFIG}:/http-perf.yml:z ${KUBE_BURNER_IMAGE} init -c http-perf.yml --uuid=${UUID}
  oc create configmap -n http-scale-client workload --from-file=workload.py
  log "Adding workload.py to the client pod"
  oc set volumes -n http-scale-client deploy/http-scale-client --type=configmap --mount-path=/workload --configmap-name=workload --add
  oc rollout status -n http-scale-client deploy/http-scale-client
  client_pod=$(oc get pod -l app=http-scale-client -n http-scale-client | grep Running | awk '{print $1}')
}

tune_liveness_probe(){
  log "Disabling cluster version and ingress operators"
  oc scale --replicas=0 -n openshift-cluster-version deploy/cluster-version-operator
  oc scale --replicas=0 -n openshift-ingress-operator deploy/ingress-operator
  log "Increasing ingress controller liveness probe period to $((RUNTIME * 2))s"
  oc set probe -n openshift-ingress --liveness --period-seconds=$((RUNTIME * 2)) deploy/router-default
  log "Scaling number of routers to ${NUMBER_OF_ROUTERS}"
  oc scale --replicas=${NUMBER_OF_ROUTERS} -n openshift-ingress deploy/router-default
  oc rollout status -n openshift-ingress deploy/router-default
}

run_mb(){
  log "Generating config with ${clients} clients ${keepalive_requests} keep alive requests and path ${URL_PATH}"
  gen_mb_config http-scale-http 80
  gen_mb_config http-scale-edge 443
  gen_mb_config http-scale-passthrough 443
  gen_mb_config http-scale-reencrypt 443
  jq -s '[.[][]]' http-scale-*.json > http-scale-mix.json
  for TERMINATION in ${TERMINATIONS}; do
      log "Copying mb config http-scale-${TERMINATION}.json to pod ${client_pod}"
      oc cp -n http-scale-client http-scale-${TERMINATION}.json ${client_pod}:/tmp/http-scale-${TERMINATION}.json
    for sample in $(seq ${SAMPLES}); do
      log "Executing sample ${sample}/${SAMPLES} from termination ${TERMINATION} with ${clients} clients and ${keepalive_requests} keepalive requests"
      oc exec -n http-scale-client -it ${client_pod} -- python3 /workload/workload.py --mb-config /tmp/http-scale-${TERMINATION}.json  --termination ${TERMINATION} --runtime ${RUNTIME} --ramp-up ${RAMP_UP} --output /tmp/results.csv --sample ${sample}
      log "Sleeping for ${QUIET_PERIOD} before next test"
      sleep ${QUIET_PERIOD}
    done
  done
}

enable_ingress_operator(){
  log "Enabling cluster version and ingress operators"
  oc scale --replicas=1 -n openshift-cluster-version deploy/cluster-version-operator
  oc scale --replicas=1 -n openshift-ingress-operator deploy/ingress-operator
}

cleanup_infra(){
  log "Deleting infrastructure"
  oc delete ns -l kube-burner-uuid=${UUID} --ignore-not-found
}

# Receives 2 arguments: namespace and port. It writes a mb configuration file named <namespace>.json
gen_mb_config(){
  if [[ ${2} == 80 ]]; then
    local SCHEME=http
  else
    local SCHEME=https
  fi
  local first=true
  (echo "["
  while read n r s p t w; do
    if [[ ${first} == "true" ]]; then
        echo "{"
        first=false
    else
        echo ",{"
    fi
    echo '"scheme": "'${SCHEME}'",
      "tls-session-reuse": '${TLS_REUSE}',
      "host": "'${n}'",
      "port": '${2}',
      "method": "GET",
      "path": "'${URL_PATH}'",
      "delay": {
        "min": 0,
        "max":0 
      },
      "keep-alive-requests": '${keepalive_requests}',
      "clients": '${clients}'
    }'
  done <<< $(oc get route -n ${1} --no-headers | awk '{print $2}')
  echo "]") | python -m json.tool > ${1}.json
}
