#!/usr/bin/env bash
set -x

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

_es=${ES_SERVER:=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com}
_es_port=${ES_PORT:=80}
_es_baseline=${ES_SERVER_BASELINE:=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com}
_es_baseline_port=${ES_PORT_BASELINE:=80}
_poll_interval=${POLL_INTERVAL:=5}
COMPARE=${COMPARE:=false}
_timeout=${TIMEOUT:=240}

if [[ -n $VERSION ]]; then
  _version=${VERSION}
else
  echo "Desired version not set. Exiting"
  exit 1
fi

if [[ -n $UUID ]]; then
  _uuid=${UUID}
else
  _uuid=$(uuidgen)
fi

if [[ ${ES_SERVER} ]] && [[ ${ES_PORT} ]] && [[ ${ES_USER} ]] && [[ ${ES_PASSWORD} ]]; then
  _es=${ES_USER}:${ES_PASSWORD}@${ES_SERVER}
fi

if [[ ${ES_SERVER_BASELINE} ]] && [[ ${ES_PORT_BASELINE} ]] && [[ ${ES_USER_BASELINE} ]] && [[ ${ES_PASSWORD_BASELINE} ]]; then
  _es_baseline=${ES_USER_BASELINE}:${ES_PASSWORD_BASELINE}@${ES_SERVER_BASELINE}
fi

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi


# check if cluster is up
date
oc get clusterversion
if [ $? -ne 0 ]; then
  echo "Workload Failed for cloud $cloud_name, Unable to connect to the cluster"
  exit 1
fi

# Get initial worker count
_init_worker_count=`oc get nodes -l node-role.kubernetes.io/worker | grep -v NAME | wc -l`

if [[ ${COMPARE} == "true" ]]; then
  echo $BASELINE_CLOUD_NAME,$cloud_name > uuid.txt
else
  echo $cloud_name > uuid.txt
fi

echo "Installing snafu in python virtual environment"

rm -rf /tmp/snafu upgrade

git clone https://github.com/cloud-bulldozer/benchmark-wrapper.git /tmp/snafu

python3 -m venv upgrade
source upgrade/bin/activate
pip3 install -e /tmp/snafu

es_index="openshift-upgrade-timings"
es=${_es}
es_port=${_es_port}
_init_version=`oc get clusterversions.config.openshift.io | grep version | awk '{print $2}'`

echo "Starting upgrade test for:"
echo "Cloud: $cloud_name"
echo "Target version: $_version"
echo "Current version $_init_version"
echo "UUID: $_uuid"

if [[ -n $TOIMAGE ]]; then
  echo "To-Image: $TOIMAGE"
fi
