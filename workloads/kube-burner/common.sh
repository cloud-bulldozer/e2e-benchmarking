#!/usr/bin/env bash
set -m
source ../../utils/common.sh
source env.sh


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
  echo "Get all management worker nodes.."
  export Q_TIME=$(date +"%s")
  export Q_NODES=""
  for n in $(curl -k --silent --globoff  ${PROM_URL}/api/v1/query?query='sum(kube_node_role{openshift_cluster_name=~"'${MGMT_CLUSTER_NAME}'",role=~"master|infra|workload"})by(node)&time='$(($Q_TIME-300))'' | jq -r '.data.result[].metric.node'); do
    Q_NODES=${n}"|"${Q_NODES};
  done
  export MGMT_NON_WORKER_NODES=${Q_NODES}
  # set time for modifier queries 
  export Q_TIME=$(($Q_TIME+600))
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
  local KUBE_BURNER_DIR 
  KUBE_BURNER_DIR=$(mktemp -d)
  if [[ ! -d ${KUBE_DIR} ]]; then
    mkdir -p ${KUBE_DIR}
  fi
  if [[ -n ${BUILD_FROM_REPO} ]]; then
    git clone --depth=1 ${BUILD_FROM_REPO} ${KUBE_BURNER_DIR}
    make -C ${KUBE_BURNER_DIR} build
    mv ${KUBE_BURNER_DIR}/bin/amd64/kube-burner ${KUBE_DIR}/kube-burner
    rm -rf ${KUBE_BURNER_DIR}
  else
    curl -sS -L ${KUBE_BURNER_URL} | tar -xzC ${KUBE_DIR}/ kube-burner
  fi
  CMD="timeout ${JOB_TIMEOUT} ${KUBE_DIR}/kube-burner init --uuid=${UUID} -c $(basename ${WORKLOAD_TEMPLATE}) --log-level=${LOG_LEVEL}"

  # When metrics or alerting are enabled we have to pass the prometheus URL to the cmd
  if [[ ${INDEXING} == "true" ]] || [[ ${PLATFORM_ALERTS} == "true" ]] ; then
    CMD+=" -u=${PROM_URL} -t ${PROM_TOKEN}"
  fi
  if [[ -n ${METRICS_PROFILE} ]]; then
    log "Indexing enabled, using metrics from ${METRICS_PROFILE}"
    envsubst < ${METRICS_PROFILE} > ${KUBE_DIR}/metrics.yml
    CMD+=" -m ${KUBE_DIR}/metrics.yml"
  fi
  if [[ ${PLATFORM_ALERTS} == "true" ]]; then
    log "Platform alerting enabled, using ${PWD}/alerts-profiles/${WORKLOAD}-${platform}.yml"
    CMD+=" -a ${PWD}/alerts-profiles/${WORKLOAD}-${platform}.yml"
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
  # Number of pods to deploy per node * number of labeled nodes - pods running
  total_pod_count=$((PODS_PER_NODE * NODE_COUNT - pod_count))
  log "Number of pods to deploy on nodes: ${total_pod_count}"
  if [[ ${1} == "heavy" ]] || [[ ${1} == *cni* ]]; then
    total_pod_count=$((total_pod_count / 2))
  fi
  if [[ ${total_pod_count} -le 0 ]]; then
    log "Number of pods to deploy <= 0"
    exit 1
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
  if [[ ${HYPERSHIFT} == "true" ]]; then
    log "Control Plane not available in HyperShift"
    exit 1
  else
    oc create ns benchmark-operator
    oc create serviceaccount kube-burner -n benchmark-operator
    oc create clusterrolebinding kube-burner-crb --clusterrole=cluster-admin --serviceaccount=benchmark-operator:kube-burner
    local certkey=`oc get secret -n openshift-etcd | grep "etcd-serving-ip" | head -1 | awk '{print $1}'`
    oc extract -n openshift-etcd secret/$certkey
    export CERTIFICATE=`base64 -w0 tls.crt`
    export PRIVATE_KEY=`base64 -w0 tls.key`
    export BEARER_TOKEN=$(oc create token -n benchmark-operator kube-burner --duration=6h || oc sa get-token kube-burner -n benchmark-operator)
  fi
}

delete_pprof_secrets() {
 rm -f tls.key tls.crt
}

delete_oldpprof_folder() {
 rm -rf pprof-data
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
  for worker_node in ${WORKER_NODE_NAMES}; do
    for p in ${split_param}; do
      oc label node $worker_node $p- 1>/dev/null
      break
    done
  done
}

prep_networkpolicy_workload() {
  export ES_INDEX_NETPOL=${ES_INDEX_NETPOL:-networkpolicy-enforcement}
  oc apply -f workloads/networkpolicy/clusterrole.yml
  oc apply -f workloads/networkpolicy/clusterrolebinding.yml
}

function generated_egress_firewall_policy(){

  EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH=${EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH:=""}
  if [[ -z $EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH ]];then
	echo "Please specify EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH for template path and file name"
	exit 1
  fi
  EGRESS_FIREWALL_POLICY_RULES_TOTAL_NUM=${EGRESS_FIREWALL_POLICY_TOTAL_NUM:="130"}
  if [[ $EGRESS_FIREWALL_POLICY_RULES_TOTAL_NUM -le 4 ]];then
	  echo "Please specify a number that large than 4 for EGRESS_FIREWALL_POLICY_RULES_TOTAL_NUM"
	  exit 1
  fi
  EGRESS_FIREWALL_POLICY_IP_SEGMENT_ALLOW=${EGRESS_FIREWALL_POLICY_IP_SEGMENT_DENY:="5.110.1"}
  EGRESS_FIREWALL_POLICY_IP_SEGMENT_DENY=${EGRESS_FIREWALL_POLICY_IP_SEGMENT_DENY:="5.112.2"}
  EGRESS_FIREWALL_POLICY_DNS_PREFIX_ALLOW=${EGRESS_FIREWALL_POLICY_DNS_PREFIX_ALLOW:="www.perfscale"}
  EGRESS_FIREWALL_POLICY_DNS_PREFIX_DENY=${EGRESS_FIREWALL_POLICY_DNS_PREFIX_ALLOW:="www.perftest"}
  #Expected set 4 types of policy rule, but already have 4 rules by default, so each type of policy rule should be (total_num - 4)/4
  #ie. 130 policy rule, 126=130-4
  #EGRESS_FIREWALL_POLICY_RULE_IP_NUM=31
  #EGRESS_FIREWALL_POLICY_RULE_DNS_NUM=126-2*31=64
  EGRESS_FIREWALL_POLICY_RULE_TYPE_SUBNUM=$(( ($EGRESS_FIREWALL_POLICY_RULES_TOTAL_NUM - 4) /4 ))
  if [[ $EGRESS_FIREWALL_POLICY_RULE_TYPE_SUBNUM -ge 254 ]];then
        EGRESS_FIREWALL_POLICY_RULE_IP_NUM=${EGRESS_FIREWALL_POLICY_IP_NUM:="254"}
  else
	EGRESS_FIREWALL_POLICY_RULE_IP_NUM=$EGRESS_FIREWALL_POLICY_RULE_TYPE_SUBNUM
  fi
        EGRESS_FIREWALL_POLICY_RULE_DNS_NUM=$(( $EGRESS_FIREWALL_POLICY_RULES_TOTAL_NUM - 4 - 2 * $EGRESS_FIREWALL_POLICY_RULE_IP_NUM))

  cat>$EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH<<EOF
kind: EgressFirewall
apiVersion: k8s.ovn.org/v1
metadata:
  name: default
spec:
  egress:
  - type: Allow
    to:
      cidrSelector: 8.8.8.8/32
  - type: Deny
    to:
      cidrSelector: 8.8.4.4/32
  - type: Allow
    to:
      dnsName: www.google.com
  - type: Deny
    to:
      dnsName: www.digitalocean.com
EOF
 #Allow Rules for IP Segment
 INDEX=1
 while [[ $INDEX -le $EGRESS_FIREWALL_POLICY_RULE_IP_NUM ]];
 do
         echo -e "  - type: Allow\n    to:\n      cidrSelector: ${EGRESS_FIREWALL_POLICY_IP_SEGMENT_ALLOW}.${INDEX}/32">>$EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH
         echo -e "  - type: Deny\n    to:\n      cidrSelector: ${EGRESS_FIREWALL_POLICY_IP_SEGMENT_DENY}.${INDEX}/32">>$EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH
	 INDEX=$(( $INDEX + 1 ))
 done
 #In case odd number divide by 2
 TOTAL_ALLOW_DNS_NUM=$(( $EGRESS_FIREWALL_POLICY_RULE_DNS_NUM/2 ))
 TOTAL_DENY_DNS_NUM=$(( $EGRESS_FIREWALL_POLICY_RULE_DNS_NUM - $TOTAL_ALLOW_DNS_NUM ))
 INDEX=1
 while [[ $INDEX -le $TOTAL_ALLOW_DNS_NUM ]];
 do
	 echo -e "  - type: Allow\n    to:\n      dnsName: ${EGRESS_FIREWALL_POLICY_DNS_PREFIX_ALLOW}${INDEX}.com">>$EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH
	 INDEX=$(( $INDEX + 1 ))
 done
 INDEX=1
 while [[ $INDEX -le $TOTAL_DENY_DNS_NUM ]];
 do
	 echo -e "  - type: Deny\n    to:\n      dnsName: ${EGRESS_FIREWALL_POLICY_DNS_PREFIX_DENY}${INDEX}.com">>$EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH
	 INDEX=$(( $INDEX + 1 ))
 done
}

function getLegcyOVNInfo()
{
  echo "Get master pod roles"
for OVNMASTER in $(oc -n openshift-ovn-kubernetes get pods -l app=ovnkube-master -o custom-columns=NAME:.metadata.name --no-headers); \
   do echo "········································" ; \
   echo "· OVNKube Master: $OVNMASTER ·" ; \
   echo "········································" ; \
   echo 'North' `oc -n openshift-ovn-kubernetes rsh -Tc northd $OVNMASTER ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound | grep Role` ; \
   echo 'South' `oc -n openshift-ovn-kubernetes rsh -Tc northd $OVNMASTER ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep Role`; \
   echo 'VMNDB Memory' `oc -n openshift-ovn-kubernetes rsh -Tc northd $OVNMASTER ovs-appctl -t /var/run/ovn/ovnnb_db.ctl memory/show`; \
   echo "····················"; \
   done

for i in $(oc get node -l node-role.kubernetes.io/master= --no-headers -oname);
do 
	echo "$i:  DB Size" ; 
	oc -n openshift-ovn-kubernetes debug $i --quiet=true -- ls -lh /host/var/lib/ovn/etc; 
	echo "----------OVSDB CLUSTERS----------";
	oc -n openshift-ovn-kubernetes debug $i --quiet=true -- grep -e '^OVSDB CLUSTER ' /host/var/lib/ovn/etc/ovnnb_db.db | cut -d' ' -f1-3 | sort -k3 -n | uniq -c | wc -l;
	echo "----------TOP 10 OVSDB CLUSTER INFO----------";
	oc -n openshift-ovn-kubernetes debug $i --quiet=true -- grep -e '^OVSDB CLUSTER ' /host/var/lib/ovn/etc/ovnnb_db.db | cut -d' ' -f1-3 | sort -k3 -n | uniq -c | sort -k1 -r -n | head -10;
	echo "----------ACL----------";
	POD=`oc -n openshift-ovn-kubernetes get po -l app=ovnkube-master -oname --field-selector=spec.host=${i#node/}`;
	oc -n openshift-ovn-kubernetes exec -c northd $POD -- sh -c 'ovn-nbctl --columns=_uuid --no-leader-only list acl | grep ^_uuid | wc -l';
	echo "----------match ACL----------";
	oc -n openshift-ovn-kubernetes exec -c northd $POD -- sh -c 'ovn-nbctl --no-leader-only --columns=match list acl | grep -c ^match';
done
}

function getOVNICDBInfo()
{
   UUID=${UUID:=""}
   echo "Get ACL From OVN DB"
   OVNKUBE_CONTROL_PLANE_POD=`oc -n openshift-ovn-kubernetes get lease ovn-kubernetes-master -o=jsonpath={.spec.holderIdentity}`
   echo OVNKUBE_CONTROL_PLANE_POD is $OVNKUBE_CONTROL_PLANE_POD
   NODE_NAME=`oc -n openshift-ovn-kubernetes get pod $OVNKUBE_CONTROL_PLANE_POD -o=jsonpath={.spec.nodeName}`
   echo "The Node of Pod $OVNKUBE_CONTROL_PLANE_POD is $NODE_NAME"
   OVNKUBE_NODE_POD=`oc -n openshift-ovn-kubernetes get pod -l app=ovnkube-node --field-selector spec.nodeName=$NODE_NAME, -ojsonpath='{..metadata.name}'`
   echo OVNKUBE_NODE_POD is $OVNKUBE_NODE_POD
   echo "----------ACL----------";
   oc -n openshift-ovn-kubernetes exec -c northd $OVNKUBE_NODE_POD -- sh -c 'ovn-nbctl --columns=_uuid --no-leader-only list acl | grep ^_uuid | wc -l';
   echo "----------match ACL----------";
   oc -n openshift-ovn-kubernetes exec -c northd $OVNKUBE_NODE_POD -- sh -c 'ovn-nbctl --no-leader-only --columns=match list acl | grep -c ^match';
   echo "----------ACL find port_group by uuid----------";
   oc -n openshift-ovn-kubernetes exec -c northd $OVNKUBE_NODE_POD -- sh -c 'ovn-nbctl find port_group|grep _uuid|wc -l';
   echo "----------ACL find address_set by uuid----------";
   oc -n openshift-ovn-kubernetes exec -c northd $OVNKUBE_NODE_POD -- sh -c 'ovn-nbctl find address_set|grep _uuid|wc -l';
   echo "----------ACL find external_ids by uuid for each namespace----------";
   oc -n openshift-ovn-kubernetes exec -c northd $OVNKUBE_NODE_POD -- sh -c "ovn-nbctl --format=table --no-heading --columns=action,priority,match find acl external_ids:k8s.ovn.org/name=${UUID}-1|wc -l";
}

function networkPolicyInitSyncDurationCheck(){
   #Check If existing pod is running
   UUID=${UUID:=""}
   WAIT_OVN_DB_SYNC_TIME=${WAIT_OVN_DB_SYNC_TIME:=""}
   WORKLOAD_TMPLATE_PATH=workloads/large-networkpolicy-egress
   INIT=1
   MAXRETRY=240
   while [[ $INIT -le $MAXRETRY ]];
   do
	unreadyNum=`oc get pods -A |grep $UUID | awk '{print $3}' | grep '0/.'|wc -l`
        if [[ $unreadyNum -eq 0 ]];then
		echo "All previous kube-burner job pod is ready"
		break
	fi
	sleep 30

	if [[ $INIT -lt $MAXRETRY ]];then
	        echo "Some kube-burner job pod isn't ready, continue to check"
        else
		echo "The retry time reach maxinum, exit"
		exit 1
        fi
	INIT=$(( $INIT + 1 ))
   done
   NODE_NUM=`oc get nodes |grep worker|wc -l`
   echo "Create recycle ns to simulate customer remove network policy and egressfirewall operation" 

   i=1
   while [[ $i -le 10 ]]
   do
	oc create ns recycle-ns${i}
	oc -n recycle-ns${i} apply -f ${WORKLOAD_TMPLATE_PATH}/deny-all.yml
        oc -n recycle-ns${i} apply -f ${WORKLOAD_TMPLATE_PATH}/case-networkpolicy-defaultport.yml
        oc -n recycle-ns${i} apply -f $EGRESS_FIREWALL_POLICY_TEMPLAT_FILE_PATH
	i=$(( $i + 1 ))
   done

   sleep 600

   echo "remove network policy and egressfirewall operation" 
   i=1
   while [[ $i -le 10 ]]
   do
        oc delete ns recycle-ns${i}
	i=$(( $i + 1 ))
   done

   if ! oc get ns |grep zero-trust-jks >/dev/null;
   then
      oc create ns zero-trust-jks;
   fi  
   if ! oc get ns |grep zero-trust-clt >/dev/null;
   then
      oc create ns zero-trust-clt;
   fi  
   oc -n zero-trust-jks apply -f ${WORKLOAD_TMPLATE_PATH}/deny-all.yml
   oc -n zero-trust-jks apply -f ${WORKLOAD_TMPLATE_PATH}/probe-detect-deployment.yaml
   oc -n zero-trust-jks apply -f ${WORKLOAD_TMPLATE_PATH}/probe-detect-service.yaml
   oc -n zero-trust-jks apply -f ${WORKLOAD_TMPLATE_PATH}/case-networkpolicy-probe-port.yml

   echo "wait for $WAIT_OVN_DB_SYNC_TIME seconds to make sure all network policy/egress firewall rule sync"
   sleep $WAIT_OVN_DB_SYNC_TIME
   oc -n zero-trust-clt apply -f ${WORKLOAD_TMPLATE_PATH}/deny-all.yml
   sleep 600
   oc -n zero-trust-clt apply -f ${WORKLOAD_TMPLATE_PATH}/probe-detect-daemonset.yaml
   oc -n zero-trust-clt apply -f ${WORKLOAD_TMPLATE_PATH}/case-networkpolicy-allowdns.yml
   oc -n zero-trust-clt apply -f ${WORKLOAD_TMPLATE_PATH}/case-networkpolicy-defaultport.yml
   
   if oc -n openshift-ovn-kubernetes get pods |grep ovnkube-master; then

      getLegcyOVNInfo
   else
      getOVNICDBInfo
   fi
   echo "----------------------TOP 15 Usage of Containers---------------------------"
   oc -n openshift-ovn-kubernetes adm top pods --containers| sort -n -r -k4 | head -15

   infraNodeNames=`oc get nodes |grep -E 'infra' |awk '{print $1}' | tr -s '\n' '|'`
   infraNodeNames=${infraNodeNames:0:-1}

   masterNodeNames=`oc get nodes |grep -E 'master' |awk '{print $1}' | tr -s '\n' '|'`
   masterNodeNames=${masterNodeNames:0:-1}
   echo "----------------------TOP Usage of Infra Node---------------------------"
   if [[ -n $infraNodeNames ]];then
      oc adm top nodes | grep -i -E "$infraNodeNames|NAME"  |sort -n -k5 
   else
      infraNodeNames="none"
   fi
   echo

   echo "----------------------TOP Usage of Master/ControlPlane Node---------------------------"
   oc adm top nodes | grep -i -E "$masterNodeNames|NAME" |sort -n -k5 
   echo

   echo "----------------------TOP Usage of Worker Node---------------------------"
   oc adm top nodes | grep -i -E -v "$masterNodeNames|$infraNodeNames" | sort -k5 -n
   echo "----------------------`date`-------------------------------"
   #Wait for max 10 minutes to check if pod is up and running
   INIT=1
   MAXRETRY=20
   while [[ $INIT -le $MAXRETRY ]];
   do
        desiredPods=`oc -n zero-trust-clt get daemonset probe-detect-ds -ojsonpath='{.status.desiredNumberScheduled}'`
        readyPods=`oc -n zero-trust-clt get daemonset probe-detect-ds -ojsonpath='{.status.numberReady}'`
        if [[ $readyPods -eq $desiredPods ]];then
		echo "All daemonset probe-detectd-ds pod is ready"
		break
	fi
	sleep 30

	if [[ $INIT -lt $MAXRETRY ]];then
	        echo "Some daemonset probe-detectd-ds pod isn't ready, continue to check"
	else 
		for podname in `oc -n probe-detect-ds get pods -oname`
		do
			oc -n probe-detect-ds logs $podname |grep -i -E 'FailedCreatePodSandBox|failed to configure pod interface|timed out waiting for OVS port binding'
	        done
	        echo "The retry time reach maxinum, exit"
	        exit 1
        fi
	INIT=$(( $INIT + 1 ))
   done
   echo "----------------------`date`-------------------------------"
}
