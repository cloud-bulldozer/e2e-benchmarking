#!/bin/bash

export platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
export cluster_version=$(oc get clusterversion | grep -o [0-9.]* | head -1)
export network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
export folder_date_time=$(TZ=UTC date +"%Y-%m-%d_%I:%M_%p")
export SNAPPY_USER_FOLDER=${SNAPPY_USER_FOLDER:=perf-ci}

if [[ -n $RUNID ]];then 
    export runid=$RUNID-
fi