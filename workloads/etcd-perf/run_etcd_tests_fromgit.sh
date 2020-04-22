#!/usr/bin/env bash
set -x

trap "rm -rf /tmp/ripsaw" EXIT
_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80
samples=5
sample=0

if [[ "${ES_SERVER}" ]]; then
  _es=${ES_SERVER}
fi

if [[ "${ES_PORT}" ]]; then
  _es_port=${ES_PORT}
fi

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

oc create ns my-ripsaw
oc create ns backpack

git clone http://github.com/cloud-bulldozer/ripsaw /tmp/ripsaw --depth 1
oc apply -f /tmp/ripsaw/deploy
oc apply -f /tmp/ripsaw/resources/backpack_role.yaml
oc apply -f /tmp/ripsaw/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc apply -f /tmp/ripsaw/resources/operator.yaml

oc adm policy add-scc-to-user -n my-ripsaw privileged -z benchmark-operator
oc adm policy add-scc-to-user -n my-ripsaw privileged -z backpack-view

cat << EOF | oc create -n my-ripsaw -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: $_es
    port: $_es_port
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  metadata:
    collection: true
    sa: backpack-view
    privileged: true
  workload:
    name: byowl
    args:
      image: "quay.io/cloud-bulldozer/fio"
      clients: 1
      commands: |
        for i in $(seq ${samples} | xargs); do
          mkdir -p /tmp/perf;
          fio --rw=write --ioengine=sync --fdatasync=1 --directory=/tmp/perf --size=22m --bs=2300 --name=test;
          sleep 5;
        done
EOF

fio_state=1
for i in {1..60}; do
  if [[ $(oc get benchmark fio-benchmark -n my-ripsaw -o jsonpath='{.status.complete}') == true ]]; then
    echo "FIO Workload done"
    fio_state=$?
    break
  fi
  sleep 30
done

if [ "$fio_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

results=$(oc logs -n my-ripsaw $(oc get pods -o name -n my-ripsaw | grep byowl) | grep "fsync\/fd" -A 7 | awk '/99.00th/{ print $3}' | sed 's/[],]//g')
units=($(oc logs -n my-ripsaw $(oc get pods -o name -n my-ripsaw | grep byowl) awk '/sync percentiles /{ print $3 }' | sed 's/[():]//g'))
for r in ${results}; do
  echo "99th fdatasync latency in sample ${sample}: ${r} ${units[${sample}]}"
  ((sample++))
done

exit 0
