#!/usr/bin/env bash
set -x

source ./common.sh

if [ $# -eq 0 ]; then
    echo "Missing Argument"
    echo "Run './run.sh build' to install hypershift and hosted clusters"
    echo "Run './run.sh clean' to cleanup already installed resources"
    exit 1
fi

prep
if [[ "$1" == "clean" ]]; then
    printf "Running Cleanup Steps"
    setup
    cleanup
elif [[ "$1" == "build" ]]; then
    echo "Set start time of prom scrape"
    export START_TIME=$(date +"%s")
    setup
    pre_flight_checks
    install

    export NODEPOOL_SIZE=$COMPUTE_WORKERS_NUMBER
    for itr in $(seq 1 $NUMBER_OF_HOSTED_CLUSTER);
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

    export MGMT_CLUSTER_PREFIX=$MGMT_CLUSTER_NAME
    for itr in $(seq 1 $NUMBER_OF_HOSTED_CLUSTER);
    do
        export HOSTED_CLUSTER_NAME=hypershift-$MGMT_CLUSTER_PREFIX-hosted-$itr
        echo "Check Hosted cluster progress..$HOSTED_CLUSTER_NAME"
        postinstall
        if [[ $ENABLE_INDEX == "true" ]]; then
            echo "Set end time of prom scrape"
            export END_TIME=$(date +"%s")
            index_mgmt_cluster_stat
        fi
    done
    echo "Downloaded kubeconfig file of hosted clusters to local.."
else
    echo "Wrong Argument"
    echo "Run './run.sh build' to install hypershift and hosted clusters"
    echo "Run './run.sh clean' to cleanup already installed resources"
    exit 1    
fi

