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
        if echo "$job_run_id" | grep -qi "scheduled"; then
            job_type="scheduled"
        elif echo "$job_run_id" | grep -qi "backfill"; then
            job_type="backfill"
        elif echo "$job_run_id" | grep -qi "dataset"; then
            job_type="dataset dependancy"
        else
            job_type="manual"
        fi
    elif [[ -n $PROW_JOB_ID ]]; then
        export ci="PROW"
        export prow_base_url="https://prow.ci.openshift.org/view/gs/origin-ci-test/logs"
        export prow_pr_base_url="https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/openshift_release"
        job_type=${JOB_TYPE}
        if [[ "${job_type}" == "presubmit" && "${JOB_NAME}" == *pull* ]]; then
            # Indicates a ci test triggered in PR against source code
            job_type="pull"
        fi
        if [[ "${job_type}" == "presubmit" && "${JOB_NAME}" == *rehearse* ]]; then
            # Indicates a rehearsel in PR against openshift/release repo
            job_type="rehearse"
        fi

    elif [[ -n $BUILD_ID ]]; then
        export ci="JENKINS"
        export build_url="${BUILD_URL}api/json"
        set +eo pipefail
        LATEST_CAUSE=$(curl -s ${build_url} | tr '\n' ' ' | jq -r '.actions[].causes[].shortDescription' 2>/dev/null | grep -v "null" | head -n 1)
        echo "latest cause $LATEST_CAUSE"
        if echo "$LATEST_CAUSE" | grep -iq "SCM"; then
            job_type="scm trigger"
        elif echo "$LATEST_CAUSE" | grep -iq "timer"; then
            job_type="time trigger"
        elif echo "$LATEST_CAUSE" | grep -iq "upstream"; then
            job_type="upstream trigger"
        elif echo "$LATEST_CAUSE" | grep -iq "user"; then
            job_type="manual trigger"
        else
            job_type="unknown"
        fi
        set -eo pipefail
    fi
    export job_type
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
    ipsec=false
    ipsecMode="Disabled"
    if result=$(oc get networks.operator.openshift.io cluster -o=jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.ipsecConfig.mode}'); then
        # If $result is empty, it is version older than 4.15
        # We need to check a level above in the jsonpath
        # If that level is not empty it means ipsec is enabled
        if [[ -z $result ]]; then
            if deprecatedresult=$(oc get networks.operator.openshift.io cluster -o=jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.ipsecConfig}'); then
                if [[ ! -z $deprecatedresult ]]; then
                    ipsec=true
                    ipsecMode="Full"
                fi
            fi
        else
            # No matter if enabled and then disabled or disabled by default,
            # this field is always shows Disabled when no IPSec
            if [[ ! $result == *"Disabled"* ]]; then
                ipsec=true
                ipsecMode=$result
            fi
        fi
    fi
}

get_fips_config(){
    fips=false
    if result=$(oc get cm cluster-config-v1 -n kube-system -o json | jq -r '.data."install-config"' | grep 'fips: ' | cut -d' ' -f2); then
        fips=$result
    fi
}

get_ocp_virt_config(){
    ocp_virt=false
    if [[ `oc get pods -n openshift-cnv -l app.kubernetes.io/component=compute | wc -l` -gt 0 ]]; then
        ocp_virt=true
    fi
}

get_ocp_virt_version_config(){
    ocp_virt_version=""
    if result=$(kubectl get csv -n openshift-cnv -o jsonpath='{.items[0].spec.version}' 2> /dev/null); then
        ocp_virt_version=$result
    fi
}

get_ocp_virt_tuning_policy_config(){
    ocp_virt_tuning_policy=""
    if result=$(kubectl get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.spec.tuningPolicy}' 2> /dev/null); then
        ocp_virt_tuning_policy=$result
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

get_stream(){
    result=$(oc version -o yaml)
    if echo "$result" | grep -iq "okd"; then
        stream="okd"
    else
        stream="ocp"
    fi
}

index_task(){
    url=$1
    uuid_dir=/tmp/$UUID
    mkdir -p "$uuid_dir"

    start_date_unix_timestamp=$(date "+%s" -d "${start_date}")
    end_date_unix_timestamp=$(date "+%s" -d "${end_date}")
    current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create base JSON
    base_json='{
        "ciSystem":"'"$ci"'",
        "uuid":"'"$UUID"'",
        "releaseStream":"'"$RELEASE_STREAM"'",
        "platform":"'"$platform"'",
        "clusterType":"'"$cluster_type"'",
        "benchmark":"'"$WORKLOAD"'",
        "masterNodesCount":'"$masters"',
        "workerNodesCount":'"$workers"',
        "infraNodesCount":'"$infra"',
        "masterNodesType":"'"$master_type"'",
        "workerNodesType":"'"$worker_type"'",
        "infraNodesType":"'"$infra_type"'",
        "totalNodesCount":'"$all"',
        "clusterName":"'"$cluster_name"'",
        "ocpVersion":"'"$cluster_version"'",
        "stream":"'"$stream"'",
        "ocpVirt":"'"$ocp_virt"'",
        "ocpVirtVersion":"'"$ocp_virt_version"'",
        "ocpVirtTuningPolicy":"'"$ocp_virt_tuning_policy"'",
        "networkType":"'"$network_type"'",
        "buildTag":"'"$task_id"'",
        "jobStatus":"'"$state"'",
        "jobType":"'"$job_type"'",
        "buildUrl":"'"$build_url"'",
        "upstreamJob":"'"$job_id"'",
        "upstreamJobBuild":"'"$job_run_id"'",
        "executionDate":"'"$execution_date"'",
        "jobDuration":"'"$duration"'",
        "startDate":"'"$start_date"'",
        "endDate":"'"$end_date"'",
        "timestamp":"'"$current_timestamp"'",
        "ipsec":"'"$ipsec"'",
        "ipsecMode":"'"$ipsecMode"'",
        "fips":"'"$fips"'",
        "encrypted":"'"$encrypted"'",
        "encryptionType":"'"$encryption"'",
        "publish":"'"$publish"'",
        "computeArch":"'"$compute_arch"'",
        "controlPlaneArch":"'"$control_plane_arch"'"
    }'

    # Ensure ADDITIONAL_PARAMS is valid JSON
    if [[ -n "$ADDITIONAL_PARAMS" ]]; then
        if ! echo "$ADDITIONAL_PARAMS" | jq . >/dev/null 2>&1; then
            echo "Error: ADDITIONAL_PARAMS is not valid JSON."
            exit 1
        fi
    else
        ADDITIONAL_PARAMS='{}' # Default to empty JSON if not set
    fi

    # Merge base_json with ADDITIONAL_PARAMS
    merged_json=$(jq -n --argjson base "$base_json" --argjson extra "$ADDITIONAL_PARAMS" '$base + $extra')

    # Save and send the merged JSON
    echo "$merged_json" >> $uuid_dir/index_data.json
    echo "$merged_json"
    curl -sS --insecure -X POST -H "Content-Type:application/json" -H "Cache-Control:no-cache" -d "$merged_json" "$url"
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
        if [[ "${JOB_TYPE}" == "presubmit" ]]; then
            build_url="${prow_pr_base_url}/${PULL_NUMBER}/${job_id}/${task_id}"
        else
            build_url="${prow_base_url}/${job_id}/${task_id}"
        fi
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
get_ocp_virt_config
if [[ "$ocp_virt" == true ]]; then
    get_ocp_virt_version_config
    get_ocp_virt_tuning_policy_config
fi
get_encryption_config
get_publish_config
get_architecture_config
get_stream
index_tasks
