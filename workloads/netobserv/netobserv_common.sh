
deploy_netobserv_operator() {
  log "deploying network-observability operator and flowcollector CR"
  git clone https://github.com/netobserv/network-observability-operator.git
  export NETOBSERV_DIR=${PWD}/network-observability-operator
  add_go_path
  log `go version`
  log $PATH
  cd ${NETOBSERV_DIR} && make deploy && cd -
  log "deploying flowcollector as service"
  oc apply -f ${NETOBSERV_DIR}/config/samples/flows_v1alpha1_flowcollector.yaml
  sleep 15
  export GF_IP=$(oc get svc goflow-kube -n network-observability -ojsonpath='{.spec.clusterIP}')
  log "goflow collector IP: ${GF_IP}"
  log "waiting 120 seconds before checking IPFIX collector IP in OVS"
  sleep 120
  get_ipfix_collector_ip

  # operate_loki "add" && \
  # operate_netobserv_console_plugin "add"
}

delete_flowcollector() {
  log "deleteing flowcollector"
  oc delete -f $NETOBSERV_DIR/config/samples/flows_v1alpha1_flowcollector.yaml
  rm -rf $NETOBSERV_DIR
  # operate_loki "remove" && \
  # operate_netobserv_console_plugin "remove"
}

operate_loki() {
  local operation=$1
  if [[ "$operation" == 'add' ]]; then
    log "installing loki via helm"
    helm upgrade --install loki grafana/loki-stack --set promtail.enabled=false && \
     oc adm policy add-scc-to-user anyuid -z loki
  else
    log "uninstalling loki"
    helm uninstall loki
  fi
}

operate_netobserv_console_plugin() {
  local operation=$1
  log "patching console operator to ${operation} netobserv-console-plugin"
  if [[ "$operation" == 'add' ]]; then
    oc patch console.operator.openshift.io cluster --type='json' -p "$(sed 's/REPLACE_CONSOLE_PLUGIN_OPS/add/' console-plugin-patch.json)"
  else
    oc patch console.operator.openshift.io cluster --type='json' -p "$(sed 's/REPLACE_CONSOLE_PLUGIN_OPS/remove/g' console-plugin-patch.json)"
  fi
}

add_go_path() {
  log "adding go bin to PATH"
  export PATH=$PATH:/usr/local/go/bin
}

run_perf_test_w_netobserv() {
  deploy_netobserv_operator
}

run_perf_test_wo_netobserv() {
  delete_flowcollector
}

get_ipfix_collector_ip(){
  ovnkubePods=$(oc get pods -l app=ovnkube-node -n openshift-ovn-kubernetes -o jsonpath='{.items[*].metadata.name}')
  for podName in $ovnkubePods; do
    OVS_IPFIX_COLLECTOR_IP=$(oc get pod/$podName -n openshift-ovn-kubernetes -o jsonpath='{.spec.containers[*].env[?(@.name=="IPFIX_COLLECTORS")].value}')
    if [[ -z "$OVS_IPFIX_COLLECTOR_IP" ]]; then
        log "IPFIX collector IP is not configured in OVS"
        exit 1
    fi
    log "$OVS_IPFIX_COLLECTOR_IP is configured for $podName"
  done
}