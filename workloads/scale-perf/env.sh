# Common
TEST_CLEANUP=${TEST_CLEANUP:-true}
export UUID=${UUID:-$(uuidgen)}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=openshift-cluster-timings
export METADATA_COLLECTION=${METADATA_COLLECTION:-false}
export CLOUD_NAME=${CLOUD_NAME:-test_cloud}
if [[ -n $UUID ]]; then
  export UUID=${UUID}
else
  export UUID=$(uuidgen)
fi

# Workload
export POLL_INTERVAL=${POLL_INTERVAL:=5}
export POST_SLEEP=${POST_SLEEP:=0}
export TIMEOUT=${TIMEOUT:=240}
export RUNS=${RUNS:=1}
export TEST_TIMEOUT=${TEST_TIMEOUT:-3600}
export TEST_CLEANUP=${TEST_CLEANUP:-true}
export WORKLOAD_NODE_ROLE=${WORKLOAD_NODE_ROLE:=worker}
