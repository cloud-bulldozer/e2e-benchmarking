#!/bin/bash

set -exo pipefail

# Help
function help(){
  printf "\n"
  printf "Usage: export <options> $0\n"
  printf "\n"
  printf "Options supported, export them as environment variables:\n"
  printf "\t ES_SERVER=str,                    str=elasticsearch server url, default: "https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443"\n"
  printf "\t ES_INDEX=str,                     str=elasticsearch index, default: perf_scale_ci\n"
  printf "\t JENKINS_USER=str,                 str=Jenkins user, default: ""\n"
  printf "\t JENKINS_API_TOKEN=str,            str=Jenkins API token to authenticate, default: ""\n"
  printf "\t JENKINS_BUILD_TAG=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in the Jenkins environment\n"
  printf "\t JENKINS_NODE_NAME=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in the Jenkins environment\n"
  printf "\t JENKINS_BUILD_URL=str,            str=jenkins job build url, it's a built-in env var and is automatically set in the Jenkins environment\n"
  printf "\t BENCHMARK_STATUS_FILE=str,        str=path to the file with benchmark status reported using key=value pairs\n"
}

# Defaults
if [[ -z $ES_SERVER ]]; then
  echo "Elastic server is not defined, using the default one: https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443"
  export ES_SERVER="https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443"
fi
if [[ -z $ES_INDEX ]]; then
  export ES_INDEX=perf-scale-ci
fi
if [[ -z $JENKINS_USER ]] || [[ -z $JENKINS_API_TOKEN ]]; then
  echo "Jenkins credentials are not defined, please check"
  help
  exit 1
fi

# Generate a uuid
export UUID=${UUID:-$(uuidgen)}

# Timestamp
timestamp=`date +"%Y-%m-%dT%T.%3N"`

# Get OpenShift cluster details
cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
masters=$(oc get nodes -l node-role.kubernetes.io/master --no-headers=true | wc -l)
workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers=true | wc -l)
workload=$(oc get nodes -l node-role.kubernetes.io/workload --no-headers=true | wc -l)
infra=$(oc get nodes -l node-role.kubernetes.io/infra --no-headers=true | wc -l)
cluster_version=$(oc get clusterversion -o jsonpath='{.items[0].status.desired.version}')
network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}')
all=$(oc get nodes  --no-headers=true | wc -l)

# Get the status and duration of the run
JOB_STATUS=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $JENKINS_BUILD_URL/api/json | jq -r '.result')
JOB_DURATION=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $JENKINS_BUILD_URL/api/json | jq -r '.duration')
UPSTREAM_JOB=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $JENKINS_BUILD_URL/api/json | jq -r '.actions[0].causes[-1].upstreamProject')
UPSTREAM_JOB_BUILD=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $JENKINS_BUILD_URL/api/json | jq -r '.actions[0].causes[-1].upstreamBuild')

# Scrape the job name and number from the build url and replace the defined vars
if [[ -n "$JENKINS_BUILD_URL" ]]; then
  JOB_NAME=$(echo $JENKINS_BUILD_URL | awk -F "job/" '{print $2}' | awk -F "/" '{print $1}')
  BUILD_NUMBER=$(echo $JENKINS_BUILD_URL | awk -F "job/" '{print $2}' | awk -F "/" '{print $2}')
fi

# Index data into Elasticsearch
if [[ -f "$BENCHMARK_STATUS_FILE" ]]; then
  while read -u 11 line;do
  benchmark_name=$(echo $line | awk -F'=' '{print $1}')
  benchmark_status=$(echo $line | awk -F'=' '{print $2}')
  curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
    "uuid" : "'$UUID'",
    "run_id" : "'${UPSTREAM_JOB}-${UPSTREAM_JOB_BUILD}'",
    "platform": "'$platform'",
    "master_count": "'$masters'",
    "worker_count": "'$workers'",
    "infra_count": "'$infra'",
    "workload_count": "'$workload'",
    "total_count": "'$all'",
    "cluster_name": "'$cluster_name'",
    "network_type": "'$network_type'",
    "cluster_version": "'$cluster_version'",
    "build_number": "'$BUILD_NUMBER'",
    "job_name": "'$JOB_NAME'",
    "node_name": "'$JENKINS_NODE_NAME'",
    "job_status": "'$JOB_STATUS'",
    "build_url": "'$JENKINS_BUILD_URL'",
    "upstream_job": "'$UPSTREAM_JOB'",
    "upstream_job_build": "'$UPSTREAM_JOB_BUILD'",
    "job_duration": "'$JOB_DURATION'",
    "benchmark_name": "'$benchmark_name'",
    "benchmark_status": "'$benchmark_status'",
    "timestamp": "'$timestamp'"
    }' $ES_SERVER/$ES_INDEX/_doc/
  done 11<$BENCHMARK_STATUS_FILE
else
  curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
    "uuid" : "'$UUID'",
    "run_id" : "'${UPSTREAM_JOB}-${UPSTREAM_JOB_BUILD}'",
    "platform": "'$platform'",
    "master_count": "'$masters'",
    "worker_count": "'$workers'",
    "infra_count": "'$infra'",
    "workload_count": "'$workload'",
    "total_count": "'$all'",
    "network_type": "'$network_type'",
    "cluster_version": "'$cluster_version'",
    "build_number": "'$BUILD_NUMBER'",
    "job_name": "'$JOB_NAME'",
    "cluster_name": "'$cluster_name'",
    "node_name": "'$JENKINS_NODE_NAME'",
    "job_status": "'$JOB_STATUS'",
    "build_url": "'$JENKINS_BUILD_URL'",
    "upstream_job": "'$UPSTREAM_JOB'",
    "upstream_job_build": "'$UPSTREAM_JOB_BUILD'",
    "job_duration": "'$JOB_DURATION'",
    "timestamp": "'$timestamp'"
    }' $ES_SERVER/$ES_INDEX/_doc/
fi
