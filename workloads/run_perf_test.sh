#!/usr/bin/env bash

oc create ns my-ripsaw

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

cat << EOF | oc create -f -
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
    port: 80
  clustername: azure
  test_user: azure-ci
  workload:
    name: "fio_distributed"
    args:
      samples: 3
      servers: 1
      pin_server: ''
      jobs:
        - write
        - read
      bs:
        - 4KiB
        - 64KiB
      numjobs:
        - 1
      iodepth: 4
      read_runtime: 60
      read_ramp_time: 5
      filesize: 1GiB
      log_sample_rate: 1000
      #storageclass: rook-ceph-block
      #storagesize: 5Gi
#######################################
#  EXPERT AREA - MODIFY WITH CAUTION  #
#######################################
#  global_overrides:
#    - key=value
  job_params:
    - jobname_match: w
      params:
        - fsync_on_close=1
        - create_on_open=1
    - jobname_match: read
      params:
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
    - jobname_match: rw
      params:
        - rwmixread=50
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
    - jobname_match: readwrite
      params:
        - rwmixread=50
        - time_based=1
        - runtime={{ fiod.read_runtime }}
        - ramp_time={{ fiod.read_ramp_time }}
#    - jobname_match: <search_string>
#      params:
#        - key=value
EOF

for i in {1..30}; do
  oc get benchmarks | grep benchmark | grep Complete
  if [ $? -eq 0 ]; then
	  echo "Workload done"
	  exit 0
  fi
  sleep 60
done

echo "Workload failed"

exit 1
