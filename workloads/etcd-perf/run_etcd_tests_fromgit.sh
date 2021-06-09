#!/usr/bin/env bash
source ../../utils/common.sh
set -x

# Removing my-ripsaw namespace, if it exists
oc delete namespace my-ripsaw --ignore-not-found

trap "rm -rf /tmp/benchmark-operator" EXIT
_es=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
latency_th=${LATENCY_TH:-10000000}
index=ripsaw-fio-results
curl_body='{"_source": false, "aggs": {"max-fsync-lat-99th": {"max": {"field": "fio.sync.lat_ns.percentile.99.000000"}}}}'

if [ ! -z ${2} ]; then
  export KUBECONFIG=${2}
fi

cloud_name=$1
if [ "$cloud_name" == "" ]; then
  cloud_name="test_cloud"
fi

echo "Starting test for cloud: $cloud_name"

rm -rf /tmp/benchmark-operator

oc create ns my-ripsaw
oc create ns backpack

git clone http://github.com/cloud-bulldozer/benchmark-operator /tmp/benchmark-operator --depth 1
oc apply -f /tmp/benchmark-operator/deploy
oc apply -f /tmp/benchmark-operator/resources/backpack_role.yaml
oc apply -f /tmp/benchmark-operator/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc apply -f /tmp/benchmark-operator/resources/operator.yaml

oc wait --for=condition=available "deployment/benchmark-operator" -n my-ripsaw --timeout=300s

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
    url: ${_es}
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

# Get the uuid of newly created etcd-fio benchmark.
long_uuid=$(get_uuid 30)
if [ $? -ne 0 ]; 
then 
  exit 1
fi

uuid=${long_uuid:0:8}

# Checks the presence of etcd-fio pod. Should exit if pod is not available.
etcd_pod=$(get_pod "app=fio-benchmark-$uuid" 300)
if [ $? -ne 0 ];
then
  exit 1
fi

check_pod_ready_state $etcd_pod 150s
if [ $? -ne 0 ];
then
  "Pod wasn't able to move into Running state! Exiting...."
  exit 1
fi

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
