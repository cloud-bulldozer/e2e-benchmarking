#!/usr/bin/env bash
set -x
source ../../utils/common.sh

_es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

echo "Removing benchmark-operator namespace, if it already exists"
oc delete namespace benchmark-operator --ignore-not-found

rm -rf /tmp/benchmark-operator

oc create ns benchmark-operator

git clone http://github.com/cloud-bulldozer/benchmark-operator /tmp/benchmark-operator
(cd /tmp/benchmark-operator && make deploy)
oc wait --for=condition=available "deployment/benchmark-controller-manager" -n benchmark-operator --timeout=300s
oc adm policy -n benchmark-operator add-scc-to-user privileged -z benchmark-operator
oc adm policy -n benchmark-operator add-scc-to-user privileged -z backpack-view

oc delete -n benchmark-operator benchmark/fio-benchmark --wait
sleep 30

cat << EOF | oc create -n benchmark-operator -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: benchmark-operator
spec:
  metadata:
    collection: true
    serviceaccount: backpack-view
    privileged: true
  elasticsearch:
    url: $_es
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  workload:
    name: "fio_distributed"
    args:
      samples: 3
      servers: 1
      jobs:
        - write
      bs:
        - 2300B
      numjobs:
        - 1
      iodepth: 1
      read_runtime: 3
      read_ramp_time: 1
      filesize: 23MiB
      log_sample_rate: 1000
#######################################
#  EXPERT AREA - MODIFY WITH CAUTION  #
#######################################
  job_params:
    - jobname_match: w
      params:
        - sync=1
        - direct=0
EOF

# Get the uuid of newly created fio benchmark.
long_uuid=$(get_uuid 30)
if [ $? -ne 0 ]; 
then 
  exit 1
fi

uuid=${long_uuid:0:8}

# Checks the presence of fio pod. Should exit if pod is not available.
fio_pod=$(get_pod "app=fio-benchmark-$uuid" 300)
if [ $? -ne 0 ];
then
  exit 1
fi

check_pod_ready_state $fio_pod 150s
if [ $? -ne 0 ];
then
  "Pod wasn't able to move into Running state! Exiting...."
  exit 1
fi

fio_state=1
for i in {1..60}; do
  oc describe -n benchmark-operator benchmarks/fio-benchmark | grep State | grep Complete
  if [ $? -eq 0 ]; then
	  echo "FIO Workload done"
          fio_state=$?
	  break
  fi
  sleep 60
done

if [ "$fio_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

rm -rf /tmp/benchmark-operator

exit 0
