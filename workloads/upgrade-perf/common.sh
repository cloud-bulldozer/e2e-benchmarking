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

_es=${ES_SERVER:=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
_es_baseline=${ES_SERVER_BASELINE:=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com}
_poll_interval=${POLL_INTERVAL:=5}
COMPARE=${COMPARE:=false}
_timeout=${TIMEOUT:=240}
export baremetalCheck=$(oc get infrastructure cluster -o json | jq .spec.platformSpec.type)

if [[ -n $UUID ]]; then
  _uuid=${UUID}
else
  _uuid=$(uuidgen)
fi

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

#Check to see if the infrastructure type is baremetal to adjust script as necessary 
if [[ "${baremetalCheck}" == '"BareMetal"' ]]; then
  echo "BareMetal infastructure: setting isBareMetal accordingly"
  export isBareMetal=true
else
  export isBareMetal=false
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

if [[ "${isBareMetal}" == "true" ]]; then
  sudo yum -y install python3.8
  python3.8 -m venv upgrade

else
  python3 -m venv upgrade
fi

source upgrade/bin/activate
pip3 install -e /tmp/snafu

export es_index="openshift-upgrade-timings"
export es=${_es}
_init_version=`oc get clusterversions.config.openshift.io | grep version | awk '{print $2}'`

echo "Starting upgrade test for:"
echo "Cloud: $cloud_name"
echo "Target version: $_version"
echo "Current version $_init_version"
echo "UUID: $_uuid"

# fail if the version to upgrade to is not set
if [[ -z $TOIMAGE ]] && [[ -z $LATEST ]] && [[ -z $TOVERSION ]]; then
  echo "Looks like the version to upgrade to is not set, please set either TOIMAGE, LATEST or TOVERSION environment vars"
  exit 1
fi

# fail if both TOIMAGE and LATEST vars are set to make sure the correct version is picked to upgrade to
if [[ -n $TOIMAGE ]] && [[ -n $LATEST ]]; then
  echo "Looks like both TOIMAGE and LATEST vars are set, please select one of the options"
  exit 1
elif [[ -n $TOIMAGE ]]; then
  echo "To-Image: $TOIMAGE"
elif [[ -n $LATEST ]]; then
  echo "LATEST option is set, upgrading to the latest version available in the channel"
fi
