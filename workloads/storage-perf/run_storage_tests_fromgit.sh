#!/usr/bin/env bash
set -x

_es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

rm -rf /tmp/ripsaw

oc create ns my-ripsaw

git clone http://github.com/cloud-bulldozer/ripsaw /tmp/ripsaw
oc apply -f /tmp/ripsaw/deploy
oc apply -f /tmp/ripsaw/resources/backpack_role.yaml
oc apply -f /tmp/ripsaw/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc apply -f /tmp/ripsaw/resources/operator.yaml

oc adm policy -n my-ripsaw add-scc-to-user privileged -z benchmark-operator
oc adm policy -n my-ripsaw add-scc-to-user privileged -z backpack-view

oc delete -n my-ripsaw benchmark/fio-benchmark --wait
sleep 30

cat << EOF | oc create -n my-ripsaw -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
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

fio_state=1
for i in {1..60}; do
  oc describe -n my-ripsaw benchmarks/fio-benchmark | grep State | grep Complete
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

rm -rf /tmp/ripsaw

exit 0
