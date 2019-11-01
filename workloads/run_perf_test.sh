#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

oc create ns my-ripsaw
oc create ns backpack

cat << EOF | oc create -f -
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: my-ripsaw
spec:
  targetNamespaces:
  - my-ripsaw
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-ripsaw
  namespace: my-ripsaw
spec:
  channel: alpha
  name: ripsaw
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

time oc apply -f https://raw.githubusercontent.com/cloud-bulldozer/ripsaw/0.0.1/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml

time oc wait --for condition=ready pods -l name=benchmark-operator -n my-ripsaw --timeout=5000s

oc get pods -n my-ripsaw

cat << EOF | oc create -n my-ripsaw -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  workload:
    name: byowl
    args:
      image: "quay.io/cloud-bulldozer/fio"
      clients: 1
      commands: "cd tmp/;for i in 1 2 3; do mkdir -p /tmp/test; fio --rw=write --ioengine=sync --fdatasync=1 --directory=test --size=22m --bs=2300 --name=test; done;"
EOF

sleep 30
uuid=$(oc get -n my-ripsaw benchmarks | grep fio-benchmark | awk '{print $4}')
oc apply -n bacakpack -f https://gist.githubusercontent.com/jtaleric/0f5fb636a3ffb59ba2176ea0c13bc6b0/raw/8930ee01f39d621a6105b11011c5a8dd75a95c60/gistfile1.txt
oc wait --for condition=ready pods -l name=backpack -n backpack --timeout=2400s
for node in $(oc get pods -n backpack --selector=name=backpack -o name); do
  pod=$(echo $node | awk -F'/' '{print $2}')
  oc -n backpack cp $kubeconfig backpack/$pod:/tmp/kubeconfig
  oc -n backpack exec $pod -- python3 stockpile-wrapper-always.py -s $_es -p $_es_port -u $uuid
done

fio_state=1
for i in {1..60}; do
  oc get -n my-ripsaw benchmarks | grep "fio-benchmark" | grep Complete
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

results=$(oc logs -n my-ripsaw pods/$(oc get pods | grep byowl|awk '{print $1}') | grep "fsync\/fd" -A 7 | grep "99.00" | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
echo $results

oc delete -n my-ripsaw benchmark/fio-benchmark
sleep 30

cat << EOF | oc create -n my-ripsaw -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
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

sleep 30
uuid=$(oc get -n my-ripsaw benchmarks | grep fio-benchmark | awk '{print $4}')
oc apply -n backpack -f https://gist.githubusercontent.com/jtaleric/0f5fb636a3ffb59ba2176ea0c13bc6b0/raw/8930ee01f39d621a6105b11011c5a8dd75a95c60/gistfile1.txt
oc wait --for condition=ready pods -l name=backpack  -n backpack --timeout=2400s
for node in $(oc get pods -n backpack --selector=name=backpack -o name); do
  pod=$(echo $node | awk -F'/' '{print $2}')
  oc -n backpack cp $KUBECONFIG backpack/$pod:/tmp/kubeconfig
  oc -n backpack exec $pod -- python3 stockpile-wrapper-always.py -s $_es -p $_es_port -u $uuid
done

fio_state=1
for i in {1..60}; do
  oc get -n my-ripsaw benchmarks | grep "fio-benchmark" | grep Complete
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

exit 0
