# Smoke test environment specifications:
export EACH_TEST_TIMEOUT=2400s

# For scale perf
ORIGINAL_WORKER_COUNT=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/workload!="" --ignore-not-found | grep -v NAME | wc -l`
export NEW_WORKER_COUNT=$((ORIGINAL_WORKER_COUNT + 1))
export SCALE=$NEW_WORKER_COUNT
export RUNS=2

# For upgrade perf
export TOVERSION=`oc get clusterversion | grep -o [0-9.]* | head -1`

# For router perf v2
export RUNTIME=5
export SAMPLES=2
export TERMINATIONS="http mix"
export SMALL_SCALE_ROUTES="10"
export SMALL_SCALE_CLIENTS="1 40"
export SMALL_SCALE_CLIENTS_MIX="1 20"
export KEEPALIVE_REQUESTS="0 1"
export QUIET_PERIOD=1s
export NODE_SELECTOR='{node-role.kubernetes.io/worker: }'
export TOLERANCY_RULES_CFG=""
