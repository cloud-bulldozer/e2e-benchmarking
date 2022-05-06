#!/usr/bin/env bash

source ../../utils/compare.sh
source ../../utils/common.sh
openshift_login
source env.sh

get_scenario(){
  # We consider a large scale scenario any cluster with more than the given threshold
  if [[ ${NUM_NODES} -ge ${LARGE_SCALE_THRESHOLD} ]]; then
    log "Large scale scenario detected: #workers >= ${LARGE_SCALE_THRESHOLD}"
    export NUMBER_OF_ROUTES=${LARGE_SCALE_ROUTES:-500}
    CLIENTS=${LARGE_SCALE_CLIENTS:-"1 20 80"}
    CLIENTS_MIX=${LARGE_SCALE_CLIENTS_MIX:-"1 10 20"}
  else
    log "Small scale scenario detected: #workers < ${LARGE_SCALE_THRESHOLD}"
    export NUMBER_OF_ROUTES=${SMALL_SCALE_ROUTES:-100}
    CLIENTS=${SMALL_SCALE_CLIENTS:-"1 40 200"}
    CLIENTS_MIX=${SMALL_SCALE_CLIENTS_MIX:-"1 20 80"}
  fi
}

deploy_infra(){
  log "Deploying benchmark infrastructure"
  WORKLOAD_NODE_SELECTOR=$(echo ${NODE_SELECTOR} | sed 's/^{\(.*\)\:.*$/\1/') # Capture between '{' and ':'
  WORKLOAD_NODE_COUNT=$(oc get node --no-headers -l ${WORKLOAD_NODE_SELECTOR} | wc -l)
  if [[ ${WORKLOAD_NODE_COUNT} -eq 0 ]]; then
    log "No nodes with label ${WORKLOAD_NODE_SELECTOR} found, proceeding to label a worker node at random."
    SELECTED_NODE=$(oc get nodes -l "node-role.kubernetes.io/worker=" -o custom-columns=:.metadata.name | tail -n1)
    log "Selected ${SELECTED_NODE} to label as ${WORKLOAD_NODE_SELECTOR}"
    oc label node ${SELECTED_NODE} ${WORKLOAD_NODE_SELECTOR}=""
  fi

  log "Downloading and extracting kube-burner binary"
  curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz kube-burner
  ./kube-burner init -c http-perf.yml --uuid=${UUID}

  log "Creating configmap from workload.py file"
  oc create configmap -n http-scale-client workload --from-file=workload.py
  log "Adding workload.py to the client pod"
  oc set volumes -n http-scale-client deploy/http-scale-client --add --type=configmap --mount-path=/workload --configmap-name=workload
  log "Waiting for http-scale-client rollout"
  oc rollout status -n http-scale-client deploy/http-scale-client
}

configure_ingress_images() {
  log "Disabling cluster version operator"
  oc scale --replicas=0 -n openshift-cluster-version deploy/cluster-version-operator

  # Scale the ingress-operator if you are changing any images (it needs to reconcile inorder to propagate new image)
  if [[ ! -z "${INGRESS_OPERATOR_IMAGE}" ]] || [[ ! -z "${HAPROXY_IMAGE}" ]]; then
    log "Scaling ingress-operator up to 1"
    oc scale --replicas=1 -n openshift-ingress-operator deploy/ingress-operator
    oc rollout status -n openshift-ingress-operator deploy/ingress-operator --timeout 120s
  fi

  # Configure the ingress operator image
  # Though we scale down the ingress operator later, we can still test ENV changes that the ingress-operator configures on the router deployment
  # So it's important we update the ingress-operator image before the router image
  if [[ ! -z "${INGRESS_OPERATOR_IMAGE}" ]]; then
    log "Replacing ingress-operator image with ${INGRESS_OPERATOR_IMAGE}"
    oc -n openshift-ingress-operator patch deploy/ingress-operator --type=strategic --patch='{"spec":{"template":{"spec":{"containers":[{"name":"ingress-operator","image":"'${INGRESS_OPERATOR_IMAGE}'"}]}}}}'
    oc rollout status -n openshift-ingress-operator deploy/ingress-operator --timeout 120s
    if [[ $? -ne 0 ]]; then
      log "ERROR: Ingress Operator failed to rollout image ${INGRESS_OPERATOR_IMAGE}"
      exit 1
    fi
  else
    log "Using the default ingress-operator image"
  fi

  # Set router image and wait for all pods in the deployment to be the correct image
  if [[ ! -z "${HAPROXY_IMAGE}" ]]; then
    log "Replacing router with ${HAPROXY_IMAGE}"
    oc -n openshift-ingress-operator patch deploy/ingress-operator --type=strategic --patch='{"spec":{"template":{"spec":{"containers":[{"name":"ingress-operator","env":[{"name":"IMAGE","value":"'${HAPROXY_IMAGE}'"}]}]}}}}'
    TIMEOUT=240
    # Monitor pod image is easier/safer than doing a rollout because the operator starts the rollout asynchronously 
    while [[ "$(oc get pods -n openshift-ingress -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | uniq)" != "${HAPROXY_IMAGE}" ]]; do
      log "Waiting for all router images to become ${HAPROXY_IMAGE}..."
      sleep 1
      if [[ "${TIMEOUT}" -eq 0 ]]; then
        log "ERROR: Timeout waiting for all router pods to use image: ${HAPROXY_IMAGE}"
	exit 1
      fi
      TIMEOUT=$((TIMEOUT-1))
    done
  else
    log "Using the default router image"
  fi

  log "Scaling ingress-operator down to 0"
  oc scale --replicas=0 -n openshift-ingress-operator deploy/ingress-operator
  log "Scaling number of routers to ${NUMBER_OF_ROUTERS}"
  oc scale --replicas=${NUMBER_OF_ROUTERS} -n openshift-ingress deploy/router-default
}

tune_liveness_probe(){
  log "Increasing ingress controller liveness probe period to $((RUNTIME * 2))s"
  oc scale --replicas=0 -n openshift-ingress deploy/router-default
  oc set probe -n openshift-ingress --liveness --period-seconds=$((RUNTIME * 2)) deploy/router-default
  log "Scaling number of routers to ${NUMBER_OF_ROUTERS}"
  oc scale --replicas=${NUMBER_OF_ROUTERS} -n openshift-ingress deploy/router-default
  oc rollout status -n openshift-ingress deploy/router-default
  # TODO: validate liveness period and image
}

tune_workload_node(){
  TUNED_NODE_SELECTOR=$(echo ${NODE_SELECTOR} | sed 's/^{\(.*\)\:.*$/\1/')
  log "${1^} tuned profile for node labeled with ${TUNED_NODE_SELECTOR}"
  sed "s#TUNED_NODE_SELECTOR#${TUNED_NODE_SELECTOR}#g" tuned-profile.yml | oc ${1} -f -
}

collect_metadata(){
  log "Collecting metadata for UUID: ${UUID}"
  git clone https://github.com/cloud-bulldozer/metadata-collector.git --depth=1
  pushd metadata-collector
  ./run_backpack.sh -x -c true -s ${ES_SERVER} -u ${UUID}
  popd
  rm -rf metadata-collector
}

run_mb(){
  # TODO: capture start time
  if [[ ${termination} == "mix" ]]; then
    gen_mb_mix_config
  else
    gen_mb_config
  fi
  log "Copying mb config http-scale-${termination}.json to pod ${client_pod}"
  oc cp -n http-scale-client http-scale-${termination}.json ${client_pod}:/tmp/http-scale-${termination}.json
  for sample in $(seq ${SAMPLES}); do
    log "Executing sample ${sample}/${SAMPLES} using termination ${termination} with ${clients} clients and ${keepalive_requests} keepalive requests"
    oc exec -n http-scale-client -it ${client_pod} -- python3 /workload/workload.py --mb-config /tmp/http-scale-${termination}.json  --termination ${termination} --runtime ${RUNTIME} --output /tmp/results.csv --sample ${sample}
    log "Sleeping for ${QUIET_PERIOD} before next test"
    sleep ${QUIET_PERIOD}
  done
  # TODO: capture end time
  # TODO: collect system metrics via kube-burner between ${startTime} & ${endTime} with metrics.yml
}

enable_ingress_operator(){
  log "Enabling cluster version and ingress operators"
  oc scale --replicas=1 -n openshift-cluster-version deploy/cluster-version-operator
  oc scale --replicas=1 -n openshift-ingress-operator deploy/ingress-operator
}

cleanup_infra(){
  log "Deleting infrastructure"
  oc delete ns -l kube-burner-uuid=${UUID} --ignore-not-found
  rm -f /tmp/temp-route*.txt http-perf.yml http-*.json
}

gen_mb_config(){
  log "Generating config for termination ${termination} with ${clients} clients ${keepalive_requests} keep alive requests and path ${URL_PATH}"
  local first=true
  if [[ ${termination} == "http" ]]; then
    local scheme=http
    local port=80
  else
    local scheme=https
    local port=443
  fi
  (echo "["
  for host in $(oc get route -n http-scale-${termination} --no-headers -o custom-columns="route:.spec.host"); do
    if [[ ${first} == "true" ]]; then
        echo "{"
        first=false
    else
        echo ",{"
    fi
    echo '"scheme": "'${scheme}'",
      "tls-session-reuse": '${TLS_REUSE}',
      "host": "'${host}'",
      "port": '${port}',
      "method": "GET",
      "path": "'${URL_PATH}'",
      "delay": {
        "min": 0,
        "max": 0
      },
      "keep-alive-requests": '${keepalive_requests}',
      "clients": '${clients}'
    }'
  done
  echo "]") | python -m json.tool > http-scale-${termination}.json
}

gen_mb_mix_config(){
  log "Generating config for termination ${termination} with ${clients} clients ${keepalive_requests} keep alive requests and path ${URL_PATH}"
  local first=true
  (echo "["
  for mix_termination in http edge passthrough reencrypt; do
    if [[ ${mix_termination} == "http" ]]; then
      local scheme=http
      local port=80
    else
      local scheme=https
      local port=443
    fi
    for host in $(oc get route -n http-scale-${mix_termination} --no-headers -o custom-columns="route:.spec.host"); do
      if [[ ${first} == "true" ]]; then
          echo "{"
          first=false
      else
          echo ",{"
      fi
      echo '"scheme": "'${scheme}'",
        "tls-session-reuse": '${TLS_REUSE}',
        "host": "'${host}'",
        "port": '${port}',
        "method": "GET",
        "path": "'${URL_PATH}'",
        "delay": {
          "min": 0,
          "max": 0
        },
        "keep-alive-requests": '${keepalive_requests}',
        "clients": '${clients}'
      }'
    done
  done
  echo "]") | python -m json.tool > http-scale-mix.json
}

test_routes(){
  log "Testing all routes before triggering the workload"
  for termination in http edge passthrough reencrypt; do
    local scheme="https://"
    if [[ ${termination} == "http" ]]; then
      local scheme="http://"
    fi
    for host in $(oc get route -n http-scale-${termination} --no-headers -o custom-columns="route:.spec.host"); do
      curl --retry 3 --connect-timeout 5 -sSk ${scheme}${host}${URL_PATH} -o /dev/null
    done
  done
}

snappy_backup() {
 log "snappy server as backup enabled"
 source ../../utils/snappy-move-results/common.sh
 csv_list=`find . -name "*.csv"` 
 json_list=`find . -name "*.json"`
 compare_file=`find . -name "compare*"`
 mkdir files_list
 cp $csv_list $compare_file $json_list http-perf.yml ./files_list
 tar -zcf snappy_files.tar.gz ./files_list
 workload=router-perf-v2 
 local snappy_path="$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/$UUID-$workload/$folder_date_time/"
 generate_metadata > metadata.json  
 ../../utils/snappy-move-results/run_snappy.sh snappy_files.tar.gz $snappy_path
 ../../utils/snappy-move-results/run_snappy.sh metadata.json $snappy_path
 store_on_elastic
 rm -rf files_list
}
