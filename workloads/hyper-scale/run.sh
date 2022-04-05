#!/usr/bin/env bash

source ./common.sh

if [ $# -eq 0 ]; then
    echo "Missing Argument"
    echo "Run './run.sh build' to install hypershift and hosted clusters"
    echo "Run './run.sh clean' to cleanup already installed resources"
    exit 1
fi

if [[ "$1" == "clean" ]]; then
    printf "Running Cleanup Steps"
    setup
    cleanup
fi

if [[ "$1" == "build" ]]; then
    setup
    install

    export NODEPOOL_SIZE=$COMPUTE_WORKERS_NUMBER
    for itr in {1..$NUMBER_OF_HOSTED_CLUSTER};
    do
        export HOSTED_CLUSTER_NAME=hypershift-$MGMT_CLUSTER_NAME-hosted-$itr
        if [ "${NODEPOOL_SIZE}" == "0" ] ; then
            echo "Create None type Hosted cluster..$HOSTED_CLUSTER_NAME"    
            create_empty_cluster
        else
            echo "Create Hosted cluster..$HOSTED_CLUSTER_NAME"
            create_cluster
        fi    
    done

    for itr in {1..$NUMBER_OF_HOSTED_CLUSTER};
    do
        export HOSTED_CLUSTER_NAME=hypershift-$MGMT_CLUSTER_NAME-hosted-$itr
        echo "Check Hosted cluster progress..$HOSTED_CLUSTER_NAME"
        postinstall
    done

    echo "Run below command to download kubeconfig file of hosted clusters"
    echo "kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-admin-kubeconfig -o json | jq -r '.data.kubeconfig' | base64 -d"
fi

