#!/usr/bin/env bash
set -x

_es=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
_es_port=80

if [[ ! -z "${ES_SERVER}" ]]; then
  _es=${ES_SERVER}
fi

if [[ ! -z "${ES_PORT}" ]]; then
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
oc apply -f /tmp/ripsaw/resources/crds/ripsaw_v1alpha1_ripsaw_crd.yaml
oc apply -f /tmp/ripsaw/resources/operator.yaml

oc get pods -n my-ripsaw

# Create Service Account with View privileges for backpack
oc delete ClusterRoleBinding/backpack-view
cat << EOF | oc create -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backpack_role
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - endpoints
  - persistentvolumeclaims
  - pods
  - replicationcontrollers
  - replicationcontrollers/scale
  - serviceaccounts
  - services
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - bindings
  - events
  - limitranges
  - namespaces/status
  - pods/log
  - pods/status
  - replicationcontrollers/status
  - resourcequotas
  - resourcequotas/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - namespaces
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - controllerrevisions
  - daemonsets
  - deployments
  - deployments/scale
  - replicasets
  - replicasets/scale
  - statefulsets
  - statefulsets/scale
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - autoscaling
  resources:
  - horizontalpodautoscalers
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - cronjobs
  - jobs
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - daemonsets
  - deployments
  - deployments/scale
  - ingresses
  - networkpolicies
  - replicasets
  - replicasets/scale
  - replicationcontrollers/scale
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - policy
  resources:
  - poddisruptionbudgets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  - networkpolicies
  verbs:
  - get
  - list
  - watch
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backpack-view
  namespace: my-ripsaw
---
apiVersion: v1
kind: Secret
metadata:
  name: backpack-view
  namespace: my-ripsaw
  annotations:
    kubernetes.io/service-account.name: backpack-view
type: kubernetes.io/service-account-token
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: backpack-view
  namespace: my-ripsaw
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: backpack_role
subjects:
- kind: ServiceAccount
  name: backpack-view
  namespace: my-ripsaw
EOF

oc adm policy add-scc-to-user -n my-ripsaw privileged -z benchmark-operator
oc adm policy add-scc-to-user -n my-ripsaw privileged -z backpack-view

oc apply -n my-ripsaw -f - <<< "
apiVersion: ripsaw.cloudbulldozer.io/v1alpha1
kind: Benchmark
metadata:
  name: fio-benchmark
  namespace: my-ripsaw
spec:
  elasticsearch:
    server: ${_es}
    port: ${_es_port}
  fio_path: /var/tmp
  clustername: ${cloud_name}
  test_user: ${cloud_name}-ci
  metadata_collection: true
  metadata_sa: backpack-view
  metadata_privileged: true
  workload:
    name: fio_distributed
    args:
      log_sample_rate: 1000
      samples: 5
      servers: 1
      jobs:
        - write
      bs:
        - 2300
      numjobs:
        - 1
      iodepth: 1
      filesize: 22m
  global_overrides:
    - fdatasync=1
    - ioengine=sync
    - direct=0
"

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
