#!/bin/bash

set -eo pipefail

setup(){
    if [[ -n $AIRFLOW_CTX_DAG_ID ]]; then
        export job_id=${AIRFLOW_CTX_DAG_ID}
        export execution_date=${AIRFLOW_CTX_EXECUTION_DATE}
        export job_run_id=${AIRFLOW_CTX_DAG_RUN_ID}
        export ci="AIRFLOW"
        # Get Airflow URL
        export airflow_base_url="http://$(kubectl get route/airflow -n airflow -o jsonpath='{.spec.host}')"
        # Setup Kubeconfig
        export KUBECONFIG=/home/airflow/auth/config
        curl -sS https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xz oc
        export PATH=$PATH:/home/airflow/.local/bin:$(pwd)
    elif [[ -n $PROW_JOB_ID ]]; then
        export ci="PROW"
        export prow_base_url="https://prow.ci.openshift.org/view/gs/origin-ci-test/logs"
    elif [[ -n $BUILD_ID ]]; then
        export ci="JENKINS"
        export build_url=${BUILD_URL}
    fi

    export UUID=$UUID
    # Elasticsearch Config
    export ES_SERVER=$ES_SERVER
    export WORKLOAD=$WORKLOAD
    export ES_INDEX=$ES_INDEX
    # Get OpenShift cluster details
    cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}') || echo "Cluster Install Failed"
    cluster_version=$(oc version -o json | jq -r '.openshiftVersion') || echo "Cluster Install Failed"
    export RELEASE_STREAM=$(oc version -o json | jq -r '.openshiftVersion' | cut -d '-' -f1-2) || echo "Cluster Install Failed"
    network_type=$(oc get network.config/cluster -o jsonpath='{.status.networkType}') || echo "Cluster Install Failed"
    platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}') || echo "Cluster Install Failed"
    cluster_type=""
    if [ "$platform" = "AWS" ]; then
        cluster_type=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.resourceTags[?(@.key=="red-hat-clustertype")].value}') || echo "Cluster Install Failed"
    fi
    if [ -z "$cluster_type" ]; then
        cluster_type="self-managed"
    fi

    masters=0
    infra=0
    workers=0
    all=0
    master_type=""
    infra_type=""
    worker_type=""

    for node in $(oc get nodes --ignore-not-found --no-headers -o custom-columns=:.metadata.name || true); do
        labels=$(oc get node "$node" --no-headers -o jsonpath='{.metadata.labels}')
        if [[ $labels == *"node-role.kubernetes.io/master"* ]]; then
            masters=$((masters + 1))
            master_type=$(oc get node "$node" -o jsonpath='{.metadata.labels.beta\.kubernetes\.io/instance-type}')
            taints=$(oc get node "$node" -o jsonpath='{.spec.taints}')

            if [[ $labels == *"node-role.kubernetes.io/worker"* && $taints == "" ]]; then
                workers=$((workers + 1))
            fi
        elif [[ $labels == *"node-role.kubernetes.io/infra"* ]]; then
            infra=$((infra + 1))
            infra_type=$(oc get node "$node" -o jsonpath='{.metadata.labels.beta\.kubernetes\.io/instance-type}')
        elif [[ $labels == *"node-role.kubernetes.io/worker"* ]]; then
            workers=$((workers + 1))
            worker_type=$(oc get node "$node" -o jsonpath='{.metadata.labels.beta\.kubernetes\.io/instance-type}')
        fi
        all=$((all + 1))
    done
}

get_ipsec_config(){
    # Get a ovnkube-master pod to try to ge the ipsec value
    ipsec=false
    ovn_pod=""
    if result=$(oc get pods -o custom-columns=name:.metadata.name -n openshift-ovn-kubernetes --no-headers=true | grep ovnkube-master -m1); then
        ovn_pod=$result
    fi
    if [[ -z "$ovn_pod" ]]; then
        if result=$(oc get pods -o custom-columns=name:.metadata.name -n openshift-ovn-kubernetes --no-headers=true | grep ovnkube-node -m1); then
            ovn_pod=$result
        fi
    fi

    # Check if the pod has the container nbdb, if it is OVNIC it won't
    # If it is a OVN the command will succed and the result will be stored in ipsec
    if result=$(oc -n openshift-ovn-kubernetes -c nbdb rsh $ovn_pod ovn-nbctl --no-leader-only get nb_global . ipsec); then
        if [[ $result == *"true"* ]]; then
            ipsec=true
        fi
    fi
}

get_fips_config(){
    fips=false
    if result=$(oc get cm cluster-config-v1 -n kube-system -o json | jq -r '.data."install-config"' | grep 'fips: ' | cut -d' ' -f2); then
        fips=$result
    fi
}

get_encryption_config(){
    # Check the apiserver for the encryption config
    # If encryption was never turned on, you won't find this config on the apiserver
    encrypted=false
    encryption=$(oc get apiserver -o=jsonpath='{.items[0].spec.encryption.type}' )
    # Check for null or empty string
    if [[ -n $encryption && $encryption != "null" ]]; then
        # If the encryption has been Turned OFF at some point
        # Then encryption type will be "identity"
        # This means that it is not encrypted
        if [[ $encryption != "identity" ]]; then
            encrypted=true
        fi
    else
        # Removing "identity" value of the encryption type
        encryption=""
    fi
}

get_publish_config(){
    publish="External"
    if result=$(oc get cm cluster-config-v1 -n kube-system -o json | jq -r '.data."install-config"' | grep 'publish' | cut -d' ' -f2 | xargs ); then
        publish=$result
    fi
}

get_architecture_config(){
    compute_arch=""
    if result=$(oc get cm cluster-config-v1 -n kube-system -o json | jq -r '.data."install-config"' | grep -A1 compute | grep architecture | cut -d' ' -f3 ); then
        compute_arch=$result
    fi

    control_plane_arch=""
    if result=$(oc get cm cluster-config-v1 -n kube-system -o json | jq -r '.data."install-config"' | grep -A1 controlPlane | grep architecture | cut -d' ' -f4 ); then
        control_plane_arch=$result
    fi
}

index_task(){

    url=$1
    uuid_dir=/tmp/$UUID
    mkdir $uuid_dir

    start_date_unix_timestamp=$(date "+%s" -d "${start_date}")
    end_date_unix_timestamp=$(date "+%s" -d "${end_date}")

    json_data='{
        "ciSystem":"'$ci'",
        "uuid":"'$UUID'",
        "releaseStream":"'$RELEASE_STREAM'",
        "platform":"'$platform'",
        "clusterType":"'$cluster_type'",
        "benchmark":"'$WORKLOAD'",
        "masterNodesCount":'$masters',
        "workerNodesCount":'$workers',
        "infraNodesCount":'$infra',
        "masterNodesType":"'$master_type'",
        "workerNodesType":"'$worker_type'",
        "infraNodesType":"'$infra_type'",
        "totalNodesCount":'$all',
        "clusterName":"'$cluster_name'",
        "ocpVersion":"'$cluster_version'",
        "networkType":"'$network_type'",
        "buildTag":"'$task_id'",
        "jobStatus":"'$state'",
        "buildUrl":"'$build_url'",
        "upstreamJob":"'$job_id'",
        "upstreamJobBuild":"'$job_run_id'",
        "executionDate":"'$execution_date'",
        "jobDuration":"'$duration'",
        "startDate":"'"$start_date"'",
        "endDate":"'"$end_date"'",
        "startDateUnixTimestamp":"'"$start_date_unix_timestamp"'",
        "endDateUnixTimestamp":"'"$end_date_unix_timestamp"'",
        "timestamp":"'"$start_date"'",
        "ipsec":"'"$ipsec"'",
        "fips":"'"$fips"'",
        "encrypted":"'"$encrypted"'",
        "encryptionType":"'"$encryption"'",
        "publish":"'"$publish"'",
        "computeArch":"'"$compute_arch"'",
        "controlPlaneArch":"'"$control_plane_arch"'"
        }'
    echo $json_data >> $uuid_dir/index_data.json
    echo "${json_data}"
    curl -sS --insecure -X POST -H "Content-Type:application/json" -H "Cache-Control:no-cache" -d "$json_data" "$url"

}

set_duration(){
    start_date="$1"
    end_date="$2"
    if [[ -z $start_date ]]; then
        start_date=$end_date
    fi

    if [[ -z $start_date || -z $end_date ]]; then
        duration=0
    else
        end_ts=$(date -u -d "$end_date" +"%s")
        start_ts=$(date -u -d "$start_date" +"%s")
        duration=$(( $end_ts - $start_ts ))
    fi
}


index_tasks(){
    if [[ -n $AIRFLOW_CTX_DAG_ID ]]; then
        task_states=$(AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR  airflow tasks states-for-dag-run $job_id $execution_date -o json)
        task_json=$( echo $task_states | jq -c ".[] | select( .task_id == \"$TASK\")")
        state=$(echo $task_json | jq -r '.state')
        task_id=$(echo $task_json | jq -r '.task_id')

        if [[ $task_id == "$AIRFLOW_CTX_TASK_ID" || $task_id == "cleanup" ]]; then
            echo "Index Task doesn't index itself or cleanup step, skipping."
        else
            start_date=$(echo $task_json | jq -r '.start_date')
            end_date=$(echo $task_json | jq -r '.end_date')
            set_duration "$start_date" "$end_date"
            encoded_execution_date=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input()))" <<< "$execution_date")
            build_url="${airflow_base_url}/task?dag_id=${job_id}&task_id=${task_id}&execution_date=${encoded_execution_date}"
            index_task "$ES_SERVER/$ES_INDEX/_doc/$job_id%2F$job_run_id%2F$task_id%2F$UUID"
        fi
     elif [[ -n $PROW_JOB_ID ]]; then
        task_id=$BUILD_ID
        job_id=$JOB_NAME
        job_run_id=$PROW_JOB_ID
        state=$JOB_STATUS
        build_url="${prow_base_url}/${job_id}/${task_id}"
        execution_date=$JOB_START
        set_duration "$JOB_START" "$JOB_END"
        index_task "$ES_SERVER/$ES_INDEX/_doc/$job_id%2F$job_run_id%2F$task_id%2F$UUID"
    elif [[ -n $BUILD_ID ]]; then
        task_id=$BUILD_ID
        job_id=$JOB_BASE_NAME
        state=$JOB_STATUS
        execution_date=$JOB_START
        set_duration "$JOB_START" "$JOB_END"
        index_task "$ES_SERVER/$ES_INDEX/_doc/$job_id%2F$task_id%2F$UUID"
    fi
}

# Defaults
if [[ -z $PROW_JOB_ID && -z $AIRFLOW_CTX_DAG_ID && -z $BUILD_ID ]]; then
    echo "Not a CI run. Skipping CI metrics to be indexed"
    exit 0
fi
if [[ -z $ES_SERVER ]]; then
  echo "Elastic server is not defined, please check"
  exit 0
fi
if [[ -z $UUID ]]; then
  echo "UUID is not present. UUID is a must for the indexing step"
  exit 0
fi

ES_INDEX=perf_scale_ci

setup
get_ipsec_config
get_fips_config
get_encryption_config
get_publish_config
get_architecture_config
index_tasks
