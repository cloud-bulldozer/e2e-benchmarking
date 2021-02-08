#smoke test environment specifications:

#for scale perf
export SCALE=6
export RUNS=1
export TIMEOUT=10
#for kube burner 
export JOB_ITERATIONS=3
export CLEANUP=true
export CLEANUP_WHEN_FINISH=true
export NODE_COUNT=4
export PODS_PER_NODE=40
#for upgrade perf
export VERSION=4.6.12
#for router perf
export PBENCH_SERVER='pbench.dev.openshift.com'
export COMPARE=false
export HTTP_TEST_SUFFIX='smoke-test'
export HTTP_TEST_SMOKE_TEST=true
