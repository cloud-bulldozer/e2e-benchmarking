#!/usr/bin/env bash
set -m
source ../../utils/common.sh
source env.sh
source ../../utils/compare.sh

openshift_login

# If INDEXING is enabled we retrive the prometheus oauth token
if [[ ${INDEXING} == "true" ]]; then
  if [[ ${HYPERSHIFT} == "false" ]]; then
    export PROM_TOKEN=$(oc create token -n openshift-monitoring prometheus-k8s --duration=6h || oc sa get-token -n openshift-monitoring prometheus-k8s || oc sa new-token -n openshift-monitoring prometheus-k8s)
  else
    export PROM_TOKEN="dummytokenforthanos"
    export HOSTED_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
  fi
fi
export UUID=${UUID:-$(uuidgen)}
export OPENSHIFT_VERSION=$(oc version -o json | jq -r '.openshiftVersion') 
export NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.status.networkType}') 
export INGRESS_DOMAIN=$(oc get IngressController default -n openshift-ingress-operator -o jsonpath='{.status.domain}' || oc get routes -A --no-headers | head -n 1 | awk {'print$3'} | cut -d "." -f 2-)

platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')

if [[ ${HYPERSHIFT} == "true" ]]; then
  # shellcheck disable=SC2143
  if oc get ns grafana-agent; then
    log "Grafana agent is already installed"
  else
    export CLUSTER_NAME=${HOSTED_CLUSTER_NAME}
    export PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
    export DAG_ID=$(oc version -o json | jq -r '.openshiftVersion')-$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}') # setting a dynamic value
    envsubst < ./grafana-agent.yaml | oc apply -f -
  fi
fi

collect_pprof() {
  sleep 50
  while [ $(oc get benchmark -n benchmark-operator kube-burner-${1}-${UUID} -o jsonpath="{.status.complete}") == "false" ]; do
    log "-----------------------checking for new pprof files--------------------------"
    oc rsync -n benchmark-operator $(oc get pod -n benchmark-operator -o name -l benchmark-uuid=${UUID}):/tmp/pprof-data $PWD/
    sleep 60
  done
}

run_workload() {
  local CMD
  curl -sS -L ${KUBE_BURNER_URL} | tar -xzC /tmp/ kube-burner
  CMD="timeout ${JOB_TIMEOUT} /tmp/kube-burner init --uuid=${UUID} -c $(basename ${WORKLOAD_TEMPLATE}) --log-level=${LOG_LEVEL}"
  local tmpdir=$(mktemp -d)
  # When metrics or alerting are enabled we have to pass the prometheus URL to the cmd
  if [[ ${INDEXING} == "true" ]] || [[ ${PLATFORM_ALERTS} == "true" ]] ; then
    CMD+=" -u=${PROM_URL} -t ${PROM_TOKEN}"
  fi
  if [[ -n ${METRICS_PROFILE} ]]; then
    log "Indexing enabled, using metrics from ${METRICS_PROFILE}"
    envsubst < ${METRICS_PROFILE} > ${tmpdir}/metrics.yml || envsubst <  ${METRICS_PROFILE} > ${tmpdir}/metrics.yml
    CMD+=" -m ${tmpdir}/metrics.yml"
  fi
  if [[ ${PLATFORM_ALERTS} == "true" ]]; then
    log "Platform alerting enabled, using ${PWD}/alert-profiles/${WORKLOAD}-${platform}.yml"
    CMD+=" -a ${PWD}/alert-profiles/${WORKLOAD}-${platform}.yml"
  fi
  pushd $(dirname ${WORKLOAD_TEMPLATE})
  local start_date=$(date +%s%3N)
  ${CMD}
  rc=$?
  popd
  if [[ ${rc} == 0 ]]; then
    RESULT=Complete
  else
    RESULT=Failed
  fi
  gen_metadata ${WORKLOAD} ${start_date} $(date +%s%3N)
}

find_running_pods_num() {
  pod_count=0
  # The next statement outputs something similar to:
  # ip-10-0-177-166.us-west-2.compute.internal:20
  # ip-10-0-250-197.us-west-2.compute.internal:17
  # ip-10-0-151-0.us-west-2.compute.internal:19
  NODE_PODS=$(kubectl get pods --field-selector=status.phase=Running -o go-template --template='{{range .items}}{{.spec.nodeName}}{{"\n"}}{{end}}' -A | awk '{nodes[$1]++ }END{ for (n in nodes) print n":"nodes[n]}')
  for worker_node in ${WORKER_NODE_NAMES}; do
    for node_pod in ${NODE_PODS}; do
      # We use awk to match the node name and then we take the number of pods, which is the number after the colon
      pods=$(echo "${node_pod}" | awk -F: '/'$worker_node'/{print $2}')
      pod_count=$((pods + pod_count))
    done
  done
  log "Total running pods across nodes: ${pod_count}"
  if [[ ${NODE_SELECTOR} =~ node-role.kubernetes.io/worker ]]; then
    # Number of pods to deploy per node * number of labeled nodes - pods running - kube-burner pod
    log "kube-burner will run on a worker node, decreasing by one the number of pods to deploy"
    total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count - 1))
  else
    # Number of pods to deploy per node * number of labeled nodes - pods running
    total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count))
  fi
  if [[ ${total_pod_count} -le 0 ]]; then
    log "Number of pods to deploy <= 0"
    exit 1
  fi
  log "Number of pods to deploy on nodes: ${total_pod_count}"
  if [[ ${1} == "heavy" ]] || [[ ${1} == *cni* ]]; then
    total_pod_count=$((total_pod_count / 2))
  fi
  export TEST_JOB_ITERATIONS=${total_pod_count}
}

cleanup() {
  log "Cleaning up benchmark assets"
  if ! oc delete ns -l kube-burner-uuid=${UUID} --grace-period=600 --timeout=${CLEANUP_TIMEOUT} 1>/dev/null; then
    log "Namespaces cleanup failure"
    rc=1
  fi
}

get_pprof_secrets() {
 local certkey=`oc get secret -n openshift-etcd | grep "etcd-serving-ip" | head -1 | awk '{print $1}'`
 oc extract -n openshift-etcd secret/$certkey
 export CERTIFICATE=`base64 -w0 tls.crt`
 export PRIVATE_KEY=`base64 -w0 tls.key`
 export BEARER_TOKEN=$(oc create token -n benchmark-operator kube-burner --duration=6h || oc sa get-token kube-burner -n benchmark-operator)
}

delete_pprof_secrets() {
 rm -f tls.key tls.crt
}

delete_oldpprof_folder() {
 rm -rf pprof-data
}

get_network_type() {
if [[ $NETWORK_TYPE == "OVNKubernetes" ]]; then
  network_ns=openshift-ovn-kubernetes
else
  network_ns=openshift-sdn
fi
}

check_metric_to_modify() {
  export div_by=1
  echo $config | grep -i memory
  if [[ $? == 0 ]]; then 
   export div_by=1048576
  fi
  echo $config | grep -i latency
  if [[ $? == 0 ]]; then
    export div_by=1000
  fi
}

run_benchmark_comparison() {
   if [[ -n ${ES_SERVER} ]] && [[ -n ${COMPARISON_CONFIG} ]]; then
     log "Installing touchstone"
     install_touchstone
     get_network_type
     export TOUCHSTONE_NAMESPACE=${TOUCHSTONE_NAMESPACE:-"$network_ns"}
     res_output_dir="/tmp/${WORKLOAD}-${UUID}"
     mkdir -p ${res_output_dir}
     final_csv=${res_output_dir}/${UUID}.csv
     for config in ${COMPARISON_CONFIG}; do
       check_metric_to_modify
       envsubst < touchstone-configs/${config} > /tmp/${config}
       COMPARISON_OUTPUT="${res_output_dir}/${config}"
       if [[ -n ${ES_SERVER_BASELINE} ]] && [[ -n ${BASELINE_UUID} ]]; then
         log "Comparing with baseline"
         compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" "/tmp/${config}" "${GEN_CSV}"
       else
         log "Querying results"
         compare ${ES_SERVER} ${UUID} "/tmp/${config}" "${GEN_CSV}"
       fi
       if [[ ${GEN_CSV} == "true" ]]; then
         python ../../utils/csv_modifier.py -c ${COMPARISON_OUTPUT} -o ${final_csv}
       fi
     done
     if [[ -n ${GSHEET_KEY_LOCATION} ]] && [[ ${GEN_CSV} == "true" ]]; then
       gen_spreadsheet ${WORKLOAD} ${final_csv} ${EMAIL_ID_FOR_RESULTS_SHEET} ${GSHEET_KEY_LOCATION}
     fi
     log "Removing touchstone"
     remove_touchstone
  fi
 }

label_node_with_label() {
  colon_param=$(echo $1 | tr "=" ":" | sed 's/:/: /g')
  export POD_NODE_SELECTOR="{$colon_param}"
  if [[ -z $NODE_COUNT ]]; then
    NODE_COUNT=$(oc get node -o name --no-headers -l ${WORKER_NODE_LABEL},node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= | wc -l )
  fi
  if [[ ${NODE_COUNT} -le 0 ]]; then
    log "Node count <= 0: ${NODE_COUNT}"
    exit 1
  fi
  WORKER_NODE_NAMES=$(oc get node -o custom-columns=name:.metadata.name --no-headers -l ${WORKER_NODE_LABEL},node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= | head -n ${NODE_COUNT})
  if [[ $(echo "${WORKER_NODE_NAMES}" | wc -l) -lt ${NODE_COUNT} ]]; then
    log "Not enough worker nodes to label"
    exit 1
  fi

  log "Labeling ${NODE_COUNT} worker nodes with $1"
  oc label node ${WORKER_NODE_NAMES} $1 --overwrite 1>/dev/null
}

unlabel_nodes_with_label() {
  split_param=$(echo $1 | tr "=" " ")
  log "Removing $1 label from worker nodes"
  for p in ${split_param}; do
    oc label node ${WORKER_NODE_NAMES} $p- 1>/dev/null
    break
  done
}

prep_networkpolicy_workload() {
  export ES_INDEX_NETPOL=${ES_INDEX_NETPOL:-networkpolicy-enforcement}
  oc apply -f workloads/networkpolicy/clusterrole.yml
  oc apply -f workloads/networkpolicy/clusterrolebinding.yml
}
