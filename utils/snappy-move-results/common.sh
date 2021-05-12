#!/bin/bash

# Get OpenShift cluster details
export cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
export masters=$(oc get nodes -l node-role.kubernetes.io/master --no-headers=true | wc -l)
export workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers=true | wc -l)
export infra=$(oc get nodes -l node-role.kubernetes.io/infra --no-headers=true | wc -l)
export platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
export cluster_version=$(oc get clusterversion | grep -o [0-9.]* | head -1)
export network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}' | tr '[:upper:]' '[:lower:]')
export folder_date_time=$(TZ=UTC date +"%Y-%m-%d_%I:%M_%p")
export SNAPPY_USER_FOLDER=${SNAPPY_USER_FOLDER:=perf-ci}

if [[ -n $RUNID ]];then 
    export runid=$RUNID-
fi

#Function to store the run id, snappy path and other cluster details on elasticsearch
store_on_elastic()
{
    if [[ -n $RUNID ]];then 
        export ES_SERVER="https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443"
        export ES_INDEX=snappy

        curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
            "run_id" : "'$RUNID'",
            "snappy_directory_url" : "'$SNAPPY_DATA_SERVER_URL/index/$SNAPPY_USER_FOLDER/$runid$platform-$cluster_version-$network_type/'",
            "snappy_folder_path" : "'$snappy_path'",
            "platform": "'$platform'",
            "cluster_name": "'$cluster_name'",
            "network_type": "'$network_type'",
            "cluster_version": "'$cluster_version'",
            "master_count": "'$masters'",
            "worker_count": "'$workers'",
            "infra_count": "'$infra'",            
            "timestamp": "'$folder_date_time'"
            }' $ES_SERVER/$ES_INDEX/_doc/    
    fi
}