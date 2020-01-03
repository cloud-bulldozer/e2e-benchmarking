#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80

if [[ "${ES_SERVER}" ]]; then
  _es=${ES_SERVER}
fi

if [[ "${ES_PORT}" ]]; then
  _es_port=${ES_PORT}
fi

kubeconfig=$2
if [ "$cloud_name" == "" ]; then
  kubeconfig="$HOME/kubeconfig"
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

oc create ns my-ripsaw
oc create ns backpack

git clone http://github.com/cloud-bulldozer/ripsaw /tmp/ripsaw
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
  metadata_collection: true
  metadata_sa: backpack-view
  metadata_privileged: true
  workload:
    name: byowl
    args:
      image: "quay.io/cloud-bulldozer/fio"
      clients: 1
      commands: "cd tmp/;for i in 1 2 3 4 5; do mkdir -p /tmp/test; fio --rw=write --ioengine=sync --fdatasync=1 --directory=test --size=22m --bs=2300 --name=test; done;"
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

results=$(oc logs -n my-ripsaw pods/$(oc get pods | grep byowl|awk '{print $1}') | grep "fsync\/fd" -A 7 | grep "99.00" | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
echo $results

rm -rf /tmp/ripsaw

exit 0
