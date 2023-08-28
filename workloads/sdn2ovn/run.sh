#!/usr/bin/env bash
set -x

source env.sh

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

echo "Migration of cluster default CNI to OVNKubernetes"

N_TYPE=$(oc get Network.operator.openshift.io cluster  -o json | jq -r '.spec.defaultNetwork.type')
echo "Current CNI is $N_TYPE"

if [[ ${N_TYPE} == "OpenShiftSDN" ]]; then
    echo "Updating .."
    oc patch Network.operator.openshift.io cluster --type='merge' \
    --patch '{ "spec": { "migration": {"networkType": "OVNKubernetes" } } }'

    echo "MCP updating.."
    echo "Setting maxUnavailable for worker mcp"
    oc patch mcp worker --type='merge' --patch '{ "spec": { "maxUnavailable": '$MAX_UNAVAILABLE_WORKER' } }'

    # _wait_for <resource> <resource_name> <desired_state> <timeout in minutes> 
    _wait_for mcp --all Updating=True 5
    _wait_for mcp master Updated=True 30

    TIME_CHECK=$(oc get nodes | grep -ic worker)
    _wait_for mcp worker Updated=True $(($TIME_CHECK*5))

    _wait_for mcp --all Updating=False 2
    _wait_for mcp --all Degraded=False 2

    echo "All MCPs are updates, updating networkType"
    oc patch Network.config.openshift.io cluster \
    --type='merge' --patch '{ "spec": { "networkType": "OVNKubernetes" } }'

    _wait_for co network Progressing=True 1

    echo "Checking daemonset status.."
    oc -n openshift-multus rollout status daemonset/multus

    MASTER_NODES=$(oc get nodes --no-headers | grep -i master | awk '{print$1}')
    WORKER_NODES=$(oc get nodes --no-headers | grep -i worker | awk '{print$1}')

    # Reboot all the nodes
    oc get pod -n openshift-machine-config-operator | grep daemon|awk '{print $1}'|xargs -i oc rsh -n openshift-machine-config-operator {} chroot /rootfs shutdown -r +1


    echo "Pause for 5 minutes and check nodes state"
    sleep 300 # 5 minutes sleep before checking master node state

    _check_nodes "-l node-role.kubernetes.io/master="
    _check_nodes "-l node-role.kubernetes.io/worker="

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

    _check_pods

    echo "Finished CNI migration"
fi
