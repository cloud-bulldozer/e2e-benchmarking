#smoke test environment specifications:
export EACH_TEST_TIMEOUT=900s

#for scale perf
export ORIGINAL_WORKER_COUNT=`oc get nodes -l node-role.kubernetes.io/worker | grep -v NAME | wc -l`
export NEW_WORKER_COUNT=$((ORIGINAL_WORKER_COUNT + 1))
export SCALE=$NEW_WORKER_COUNT
export RUNS=1

#for kube burner 
export JOB_ITERATIONS=3
export CLEANUP=true
export CLEANUP_WHEN_FINISH=true
export NODE_COUNT=`oc get nodes -l node-role.kubernetes.io/worker | grep -v NAME | wc -l`
nodes=$(oc get nodes -l node-role.kubernetes.io/worker -o name)
for n in ${nodes}; do
  pods_in_node=$(oc get pod --field-selector=spec.nodeName=${n} -A --field-selector=status.phase=Running | wc -l)
  pod_count=$((pod_count+pods_in_node))
done
# Create only 10 pods
export PODS_PER_NODE=$((pod_count / NODE_COUNT + 10))

#for upgrade perf
export VERSION=`oc get clusterversion | grep -o [0-9.]* | head -1`

#for router perf
export PBENCH_SERVER='pbench.dev.openshift.com'
export COMPARE=false
export HTTP_TEST_SUFFIX='smoke-test'
export HTTP_TEST_SMOKE_TEST=true
export HTTP_TEST_ROUTE_TERMINATION='http edge mix'
export HTTP_TEST_RUNTIME=10

# For router perf v2
export NUMBER_OF_ROUTES=10
export RUNTIME=10
export SAMPLES=2
export TERMINATIONS=http
export KEEPALIVE_REQUESTS="1 40"
export CLIENTS="1 10"
export QUIET_PERIOD=1s
export NODE_SELECTOR='{node-role.kubernetes.io/worker: }'
