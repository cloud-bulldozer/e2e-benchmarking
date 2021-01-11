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

_es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
_es_baseline=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
_metadata_collection=${METADATA_COLLECTION:=false}
_poll_interval=${POLL_INTERVAL:=5}
_post_sleep=${POST_SLEEP:=0}
COMPARE=${COMPARE:=false}
_timeout=${TIMEOUT:=240}
_runs=${RUNS:=3}

if [[ -n $SCALE ]]; then
  _scale=${SCALE}
else
  echo "Scale target not set. Exiting"
  exit 1
fi

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

echo "Starting test for cloud: $cloud_name"

rm -rf /tmp/benchmark-operator

oc create ns my-ripsaw

git clone http://github.com/cloud-bulldozer/benchmark-operator /tmp/benchmark-operator
oc apply -f /tmp/benchmark-operator/deploy
oc apply -f /tmp/benchmark-operator/resources/backpack_role.yaml
oc apply -f /tmp/benchmark-operator/resources/scale_role.yaml
oc apply -f /tmp/benchmark-operator/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml

if [[ $(oc get nodes -l node-role.kubernetes.io/workload | wc -l) -gt 1 ]]; then
  echo "      tolerations:
      - key: role
        value: workload
        effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/workload
                operator: In
                values:
                - ""
" >> /tmp/benchmark-operator/resources/operator.yaml
fi

oc apply -f /tmp/benchmark-operator/resources/operator.yaml

oc wait --for=condition=available "deployment/benchmark-operator" -n my-ripsaw --timeout=300s

oc adm policy -n my-ripsaw add-scc-to-user privileged -z benchmark-operator
oc adm policy -n my-ripsaw add-scc-to-user privileged -z backpack-view
