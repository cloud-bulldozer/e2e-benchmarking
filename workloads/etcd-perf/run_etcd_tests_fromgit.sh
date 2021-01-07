#!/usr/bin/env bash
set -x

trap "rm -rf /tmp/ripsaw" EXIT
_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80
latency_th=${LATENCY_TH:-10000000}
index=ripsaw-fio-results
curl_body='{"_source": false, "aggs": {"max-fsync-lat-99th": {"max": {"field": "fio.sync.lat_ns.percentile.99.000000"}}}}'

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

rm -rf /tmp/ripsaw

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
  name: etcd-fio
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: ${_es}
    port: ${_es_port}
  clustername: ${cloud_name}
  test_user: ${cloud_name}-ci
  metadata:
    collection: true
    serviceaccount: backpack-view
    privileged: true
  hostpath: /var/lib/fio-etcd
  workload:
    name: fio_distributed
    args:
      iodepth: 1
      log_sample_rate: 1000
      samples: 5
      servers: 1
      jobs:
        - write
      bs:
        - 2300
      numjobs:
        - 1
      filesize: 22Mib
  global_overrides:
    - fdatasync=1
    - ioengine=sync
    - direct=0
EOF

fio_state=1
for i in {1..60}; do
  if [[ $(oc get benchmark -n my-ripsaw etcd-fio -o jsonpath='{.status.complete}') == true ]]; then
    echo "FIO Workload done"
    fio_state=$?
    uuid=$(oc get benchmark -n my-ripsaw etcd-fio -o jsonpath="{.status.uuid}")
    break
  fi
  sleep 30
done

if [ "$fio_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

fsync_lat=$(curl -s ${_es}/${index}/_search?q=uuid:${uuid} -H "Content-Type: application/json" -d "${curl_body}" | python -c 'import sys,json;print(int(json.loads(sys.stdin.read())["aggregations"]["max-fsync-lat-99th"]["value"]))')
echo "Max 99th fsync latency observed: ${fsync_lat} ns"
if [[ ${fsync_lat} -gt ${latency_th} ]]; then
  echo "Latency greater than configured threshold: ${latency_th} ns"
  exit 1
fi

exit 0
