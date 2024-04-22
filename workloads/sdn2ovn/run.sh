#!/usr/bin/env bash
set -x

source env.sh

export ES_SERVER="${https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}"
export _es_index="${ES_INDEX:-managedservices-timings}"
export UUID="${UUID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
export TEMP_DIR="$(mktemp -d)"
export VERSION="$(oc version -o json | jq -r .openshiftVersion)"

# _wait_for <resource> <resource_name> <desired_state> <timeout in minutes>
_wait_for(){
    echo "Waiting for $2 $1 to be $3 in $4 Minutes"
    oc wait --for=condition=$3 --timeout=$4m $1 $2
}

_check_nodes(){
    _wait_for nodes "$1" Ready 1200 
}

_check_pods(){
    ITR=0
    while [ ${ITR} -le 10 ] ; do # checks for 10 minutes
        NUM_OF_PODS=$(oc get pods -A -o wide --no-headers | grep -iv running | grep -iv completed | wc -l)
        if [ ${NUM_OF_PODS} -eq 0 ] ; then
            echo "All pods running now.."
            return 0
        else
            echo "Still few pods are not running.."
            ITR=$((${ITR}+1))
            sleep 60
        fi
    done
    echo "Still some/few pods are at pending/crashloop state"
    oc get pods -A -o wide | grep -iv running | grep -iv completed
    exit 1    
}

_index_results(){
    METADATA=$(cat <<EOF
{
  "uuid": "${UUID}",
  "cluster_name": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
  "before_network_type": "$3",
  "after_network_type": "$4",
  "network_migration_duration": "$1",
  "mcp_duration": "$2",
  "master_count": "$(oc get node -l node-role.kubernetes.io/master= --no-headers 2>/dev/null | wc -l)",
  "worker_count": "$(oc get node --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker="" 2>/dev/null | wc -l)",
  "infra_count": "$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
  "total_node_count": "$(oc get nodes --no-headers 2>/dev/null | wc -l)",
  "timestamp": "$(date +%s%3N)"
}
EOF
)
    printf "Indexing installation timings to ${ES_SERVER}/${_es_index}"
    curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${_es_index}/_doc -d "${METADATA}" -o /dev/null
    return 0
}

echo "Migration of cluster default CNI to OVNKubernetes"

echo "Take back up of cluster network configuration"
oc get Network.config.openshift.io cluster -o yaml > $TEMP_DIR/cluster-openshift-sdn.yaml
BEFORE_N_TYPE=$(oc get Network.operator.openshift.io cluster  -o json | jq -r '.spec.defaultNetwork.type')
echo "Current CNI is $N_TYPE"

if [[ ${BEFORE_N_TYPE} == "OpenShiftSDN" ]]; then

    echo "Updating .."
    oc patch Network.operator.openshift.io cluster --type='merge' \
    --patch '{ "spec": { "migration": {"networkType": "OVNKubernetes" } } }'

    echo "MCP updating.."
    echo "Setting maxUnavailable for worker mcp"
    MCP_START_TIME=$(date +%s)
    oc patch mcp worker --type='merge' --patch '{ "spec": { "maxUnavailable": '$MAX_UNAVAILABLE_WORKER' } }'

    # _wait_for <resource> <resource_name> <desired_state> <timeout in minutes> 
    _wait_for mcp --all Updating=True 30
    _wait_for mcp master Updated=True 30
    _wait_for mcp master Updating=False 30
    _wait_for mcp master Degraded=False 10

    TIME_CHECK=$(oc get nodes | grep -ic worker)
    _wait_for mcp worker Updated=True $(($TIME_CHECK*5))
    _wait_for mcp worker Updating=False 30
    _wait_for mcp worker Degraded=False 10


    MCP_STOP_TIME=$(date +%s)
    MCP_DURATION=$((MCP_STOP_TIME - MCP_START_TIME))

    echo "All MCPs are updated, updating networkType"
    NW_MIGRATION_START=$(date +%s)

    oc patch Network.config.openshift.io cluster \
    --type='merge' --patch '{ "spec": { "networkType": "OVNKubernetes" } }'
    _wait_for co network Progressing=True 1

    echo "Checking daemonset status.."
    oc -n openshift-multus rollout status daemonset/multus

    master_nodes=$(oc get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/master=="")].metadata.name}')
    infra_nodes=$(oc get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/infra=="")].metadata.name}')
    worker_nodes=$(oc get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/worker=="")].metadata.name}')
    daemonset_name="machine-config-daemon"
    delay=1

    # Reboot master nodes
    for node in $master_nodes; do
        pods_on_node=$(oc get pods -n openshift-machine-config-operator -o jsonpath='{.items[?(@.spec.nodeName=="'$node'")].metadata.name}' -l k8s-app=$daemonset_name)
        if [[ -n $pods_on_node ]]; then
            echo "reboot master node $node in ${delay}m"
            until oc rsh -n openshift-machine-config-operator "$pods_on_node" chroot /rootfs shutdown -r +$delay; do echo "cannot reboot node $node, retry"&&sleep 3; done
            delay=$((delay+3))
        fi
    done

    delay=1
    # Reboot infra nodes, give 3 mins each
    for node in $infra_nodes; do
        pods_on_node=$(oc get pods -n openshift-machine-config-operator -o jsonpath='{.items[?(@.spec.nodeName=="'$node'")].metadata.name}' -l k8s-app=$daemonset_name)
        if [[ -n $pods_on_node ]]; then
            echo "reboot master node $node in ${delay}m"
            until oc rsh -n openshift-machine-config-operator "$pods_on_node" chroot /rootfs shutdown -r +$delay; do echo "cannot reboot node $node, retry"&&sleep 3; done
            delay=$((delay+3))
        fi
    done

    delay=5
    # Reboot worker nodes
    for node in $worker_nodes; do
        pods_on_node=$(oc get pods -n openshift-machine-config-operator -o jsonpath='{.items[?(@.spec.nodeName=="'$node'")].metadata.name}' -l k8s-app=$daemonset_name)
        if [[ -n $pods_on_node ]]; then
            echo "reboot worker node $node in ${delay}m"
            until oc rsh -n openshift-machine-config-operator "$pods_on_node" chroot /rootfs shutdown -r +$delay; do echo "cannot reboot node $node, retry"&&sleep 3; done
        fi
    done

    echo "Pause for 5 minutes and check nodes state"
    sleep 300 # 5 minutes sleep before checking master node state

    _check_nodes "-l node-role.kubernetes.io/master="
    _check_nodes "-l node-role.kubernetes.io/worker="
    _check_nodes "-l node-role.kubernetes.io/infra="

    _wait_for mcp --all Updated=True 10

    echo "Check Network status"
    oc get network.config/cluster -o json | jq -r '.status.networkType'

    echo "Wait till all operators are available"
    _wait_for co --all Available=True 10
    _wait_for co --all Progressing=False 10
    _wait_for co --all Degraded=False 10

    echo "Remove SDN specs and project"
    oc patch Network.operator.openshift.io cluster --type='merge' \
    --patch '{ "spec": { "migration": null } }'
    oc patch Network.operator.openshift.io cluster --type='merge' \
    --patch '{ "spec": { "defaultNetwork": { "openshiftSDNConfig": null } } }'
    oc delete namespace openshift-sdn
    NW_MIGRATION_STOP=$(date +%s)
    NW_MIGRATION_DURATION=$((NW_MIGRATION_STOP - NW_MIGRATION_START - 300))

    _check_pods

    echo "Finished CNI migration"
    AFTER_N_TYPE=$(oc get Network.operator.openshift.io cluster  -o json | jq -r '.spec.defaultNetwork.type')
    _index_results "$NW_MIGRATION_DURATION" "$MCP_DURATION" "$BEFORE_N_TYPE" "$AFTER_N_TYPE" "$VERSION"
fi
