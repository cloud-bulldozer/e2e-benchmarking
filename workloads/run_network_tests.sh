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

cat << EOF | oc create -f -
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: ripsawgroup
  namespace: my-ripsaw
spec:
  targetNamespaces:
  - my-ripsaw
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ripsaw
  namespace: my-ripsaw
spec:
  channel: alpha
  name: ripsaw
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

sleep 90

oc wait --for condition=ready pods -l name=benchmark-operator -n my-ripsaw --timeout=2400s

server=""
client=""
pin=false
if [[ $(oc get nodes | grep worker | wc -l) -gt 1 ]]; then
  server=$(oc describe nodes/$(oc get nodes | grep worker | tail -1 | awk '{print $1}') | grep hostname | awk -F= '{print $2}')
  client=$(oc describe nodes/$(oc get nodes | grep worker | head -1 | awk '{print $1}') | grep hostname | awk -F= '{print $2}')
  pin=true
fi

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

oc adm policy add-scc-to-user privileged -z benchmark-operator
oc adm policy add-scc-to-user privileged -z backpack-view

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
  metadata_collection: true
  metadata_sa: backpack-view
  metadata_privileged: true
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
