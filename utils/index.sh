#!/bin/bash

set -eo pipefail

# Function to download and use ocp-metadata tool
# This tool efficiently gathers OpenShift cluster metadata in a single call
# Provides: platform, clusterType, ocpVersion, masterNodesCount, workerNodesCount,
#           totalNodes, sdnType, clusterName, fips, ipsec, publish, architecture, etc.
# See: https://github.com/cloud-bulldozer/go-commons
get_ocp_metadata(){
    OCP_METADATA_VERSION=${OCP_METADATA_VERSION:-"v2.3.6"}
    OCP_METADATA_TOOL="ocp-metadata-linux-amd64"
    OCP_METADATA_URL="https://github.com/cloud-bulldozer/go-commons/releases/download/${OCP_METADATA_VERSION}/${OCP_METADATA_TOOL}"

    # Download ocp-metadata tool if not already present
    if [[ ! -f "${OCP_METADATA_TOOL}" ]]; then
        echo "Downloading ocp-metadata tool from ${OCP_METADATA_URL}..."
        curl -sL "${OCP_METADATA_URL}" -o "${OCP_METADATA_TOOL}"
        chmod +x "${OCP_METADATA_TOOL}"
    fi

    # Run ocp-metadata and capture output as JSON
    OCP_METADATA_JSON=$(./${OCP_METADATA_TOOL})

    # Export the JSON for later use in index_task()
    export OCP_METADATA_JSON

    # Extract RELEASE_STREAM for setup function
    cluster_version=$(echo "$OCP_METADATA_JSON" | jq -r '.ocpVersion // ""')
    export RELEASE_STREAM=$(echo "$cluster_version" | cut -d '-' -f1-2)
}

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
        get_prowjob_info
        if [[ "${job_type}" == "presubmit" && "${JOB_NAME}" == *pull* ]]; then
            # Indicates a ci test triggered in PR against source code
            job_type="pull"
        fi
        if [[ "${job_type}" == "presubmit" && "${JOB_NAME}" == *rehearse* ]]; then
            # Indicates a rehearsel in PR against openshift/release repo
            job_type="rehearse"
        fi
        # Handle cases where a periodic job iw triggered via pull request
        if [[ "${job_type}" == "periodic" ]]; then
            if [[ "$pull_number" -ne 0 ]]; then
                job_type="pull"
            fi
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
    # Prow job info
    export organization=$organization
    export repository=$repository
    export pull_number=$pull_number
    # Elasticsearch Config
    export ES_SERVER=$ES_SERVER
    export WORKLOAD=$WORKLOAD
    export ES_INDEX=$ES_INDEX

    # Get OpenShift cluster metadata using ocp-metadata tool
    get_ocp_metadata

    # Get infra node information (not provided by ocp-metadata)
    infra=0
    infra_type=""
    for node in $(oc get nodes --ignore-not-found --no-headers -o custom-columns=:.metadata.name || true); do
        labels=$(oc get node "$node" --no-headers -o jsonpath='{.metadata.labels}')
        if [[ $labels == *"node-role.kubernetes.io/infra"* ]]; then
            infra=$((infra + 1))
            infra_type=$(oc get node "$node" -o jsonpath='{.metadata.labels.beta\.kubernetes\.io/instance-type}')
        fi
    done

}

# Function to extract infor from the prowjob.json file
get_prowjob_info() {
    if [[ "${job_type}" == "presubmit" ]]; then
        pull_number=$PULL_NUMBER
        organization=$REPO_OWNER
        repository=$REPO_NAME
    else
        prow_artifacts_base_url="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/test-platform-results/logs"
        job_id=$JOB_NAME
        task_id=$BUILD_ID
        prowjobjson_file="${PWD}/prowjob.json"
        prowjobjson_url="${prow_artifacts_base_url}/${job_id}/${task_id}/prowjob.json"

        curl -s $prowjobjson_url -o $prowjobjson_file

        # Test if the file is valid
        if result=$(cat $prowjobjson_file | jq); then
            # Read the file and parse it with jq
            pull_number=$(jq -r '.metadata.labels."prow.k8s.io/refs.pull" // "0"' "$prowjobjson_file")
            organization=$(jq -r '.metadata.labels."prow.k8s.io/refs.org" // ""' "$prowjobjson_file")
            repository=$(jq -r '.metadata.labels."prow.k8s.io/refs.repo" // ""' "$prowjobjson_file")
        else
            pull_number=0
            organization=""
            repository=""
        fi
    fi
}

# Functions for metadata not provided by ocp-metadata tool

get_osimage_config(){
    osimage=$(oc get node -o jsonpath='{.items[0].status.nodeInfo.osImage}')
}

get_ocp_virt_config(){
    ocp_virt=false
    if [[ `oc get pods -n openshift-cnv -l app.kubernetes.io/component=compute | wc -l` -gt 0 ]]; then
        ocp_virt=true
    fi
}

get_ocp_virt_version_config(){
    if result=$(kubectl get csv -n openshift-cnv -o jsonpath='{.items[0].spec.version}' 2> /dev/null); then
        ocp_virt_version=$result
    fi
}

get_ocp_virt_tuning_policy_config(){
    if result=$(kubectl get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.spec.tuningPolicy}' 2> /dev/null); then
        ocp_virt_tuning_policy=$result
    fi
}

get_ovn_version(){
    if result=$(oc exec -n openshift-ovn-kubernetes   $(oc get pod -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{.items[0].metadata.name}')   -- ovn-controller --version   | grep "^ovn-controller" | awk '{print $2}' 2> /dev/null); then
        ovn_version=$result
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
    echo "$UUID" >> "/tmp/$WORKLOAD-uuid.txt"

    start_date_unix_timestamp=$(date "+%s" -d "${start_date}")
    end_date_unix_timestamp=$(date "+%s" -d "${end_date}")
    current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Start with ocp-metadata JSON and add additional fields
    # Create additional fields JSON for data not in ocp-metadata
    additional_fields='{
        "ciSystem":"'"$ci"'",
        "uuid":"'"$UUID"'",
        "releaseStream":"'"$RELEASE_STREAM"'",
        "benchmark":"'"$WORKLOAD"'",
        "infraNodesCount":'"$infra"',
        "infraNodesType":"'"$infra_type"'",
        "stream":"'"$stream"'",
        "osImage":"'"$osimage"'",
        "ocpVirt":"'"$ocp_virt"'",
        "ocpVirtVersion":"'"$ocp_virt_version"'",
        "ocpVirtTuningPolicy":"'"$ocp_virt_tuning_policy"'",
        "ovnVersion":"'"$ovn_version"'",
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
        "encrypted":"'"$encrypted"'",
        "encryptionType":"'"$encryption"'",
        "pullNumber":"'"$pull_number"'",
        "organization":"'"$organization"'",
        "repository":"'"$repository"'"
    }'

    # Rename fields from ocp-metadata to match expected format
    # sdnType -> networkType in ocp-metadata JSON
    base_json=$(echo "$OCP_METADATA_JSON" | jq '. + {networkType: .sdnType} | del(.sdnType)')
    # Merge with additional fields
    base_json=$(jq -n --argjson ocp "$base_json" --argjson extra "$additional_fields" '$ocp + $extra')

    # Ensure ADDITIONAL_PARAMS is valid JSON
    if [[ -n "$ADDITIONAL_PARAMS" ]]; then
        if ! echo "$ADDITIONAL_PARAMS" | jq . >/dev/null 2>&1; then
            echo "Error: ADDITIONAL_PARAMS is not valid JSON."
            exit 1
        fi
    else
        ADDITIONAL_PARAMS='{}' # Default to empty JSON if not set
    fi

    # Merge base_json with ADDITIONAL_PARAMS and KUBE_BURNER_WORKLOAD_CONFIG
    if [[ -n "$KUBE_BURNER_WORKLOAD_CONFIG" ]]; then
        if ! echo "$KUBE_BURNER_WORKLOAD_CONFIG" | jq . >/dev/null 2>&1; then
            echo "Error: KUBE_BURNER_WORKLOAD_CONFIG is not valid JSON."
            exit 1
        fi
    else
        KUBE_BURNER_WORKLOAD_CONFIG='{}'
    fi
    merged_json=$(jq -n --argjson base "$base_json" --argjson extra "$ADDITIONAL_PARAMS" --argjson kbcfg "$KUBE_BURNER_WORKLOAD_CONFIG" '$base + $extra + $kbcfg')

    # Save and send the merged JSON
    echo "$merged_json" >> $uuid_dir/index_data.json
    echo "$merged_json"

    if [[ -z $ES_SERVER ]]; then
        echo "Elastic server is not defined, please check"
        exit 0
    fi

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
if [[ -z $UUID ]]; then
    echo "UUID is not present. UUID is a must for the indexing step"
    exit 0
fi

ES_INDEX=${ES_METADATA_INDEX:-perf_scale_ci}

setup

# Get additional metadata not provided by ocp-metadata
get_osimage_config
get_ocp_virt_config
# address `ocp_virt_version: unbound variable when ocp_virt=false
ocp_virt_version=""
ocp_virt_tuning_policy=""
if [[ "$ocp_virt" == true ]]; then
    get_ocp_virt_version_config
    get_ocp_virt_tuning_policy_config
fi
get_ovn_version
get_encryption_config
get_stream
index_tasks
