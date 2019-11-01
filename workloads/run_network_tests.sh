#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80
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

oc apply -f https://raw.githubusercontent.com/cloud-bulldozer/ripsaw/0.0.1/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc wait --for condition=ready pods -l name=benchmark-operator -n my-ripsaw --timeout=2400s


server=""
client=""
pin=false
if [[ $(oc get nodes | grep worker | wc -l) -gt 1 ]]; then
server=$(oc describe nodes/$(oc get nodes | grep worker | tail -1 | awk '{print $1}') | grep hostname | awk -F= '{print $2}')
client=$(oc describe nodes/$(oc get nodes | grep worker | head -1 | awk '{print $1}') | grep hostname | awk -F= '{print $2}')
pin=true
fi

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: uperf-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
  clustername: $cloud_name
  test_user: ${cloud_name}-ci
  workload:
    name: uperf
    args:
      hostnetwork: false
      serviceip: false
      pin: $pin
      pin_server: "$server"
      pin_client: "$client"
      multus:
        enabled: false
      samples: 3
      pair: 1
      nthrs:
        - 1
      protos:
        - tcp
        - udp
      test_types:
        - stream
        - rr
      sizes:
        - 64
        - 1024
        - 16384
      runtime: 60
EOF

sleep 30
uuid=$(oc get -n my-ripsaw benchmarks | grep uperf-benchmark | awk '{print $4}')
oc apply -f https://gist.githubusercontent.com/jtaleric/0f5fb636a3ffb59ba2176ea0c13bc6b0/raw/8930ee01f39d621a6105b11011c5a8dd75a95c60/gistfile1.txt
oc wait --for condition=ready pods -l name=backpack  -n backpack --timeout=2400s
for node in $(oc get pods -n backpack --selector=name=backpack -o name); do
  pod=$(echo $node | awk -F'/' '{print $2}')
  oc cp $kubeconfig backpack/$pod:/tmp/kubeconfig
  oc -n backpack exec $pod -- python3 stockpile-wrapper-always.py -s $_es -p $_es_port -u $uuid
done

uperf_state=1
for i in {1..120}; do
  oc get -n my-ripsaw benchmarks | grep "uperf-benchmark" | grep Complete
  if [ $? -eq 0 ]; then
	  echo "Workload done"
          oc logs -n my-ripsaw pods/$(oc get pods | grep client|awk '{print $1}')
          uperf_state=$?
	  break
  fi
  sleep 60
done

if [ "$uperf_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi


exit 0
