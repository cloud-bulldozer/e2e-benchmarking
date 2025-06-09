# Common

TEST_CLEANUP=${TEST_CLEANUP:-true}
export ES_INDEX=ripsaw-uperf-results
export METADATA_COLLECTION=${METADATA_COLLECTION:-true}
# Metadata collection can sometimes cause port collisions in uperf when running in targeted mode
# It is recommended to run it with targeted set to false
export METADATA_TARGETED=${METADATA_TARGETED:-false}
export SYSTEM_METRICS_COLLECTION=${SYSTEM_METRICS_COLLECTION:-false}
export NETWORK_TYPE=$(oc get network.config/cluster -o jsonpath='{.status.networkType}') 

# Workload
export WORKLOAD=${WORKLOAD:-smoke}
export NETWORK_POLICY=${NETWORK_POLICY:=false}
export MULTI_AZ=${MULTI_AZ:=true}
export HOSTNETWORK=false
export SERVICEIP=false
export SERVICETYPE=${SERVICETYPE:-clusterip}
export ADDRESSPOOL=${ADDRESSPOOL:-addresspool-l2}
export SERVICE_ETP=${SERVICE_ETP:-Cluster}
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}
export SAMPLES=${SAMPLES:-3}
export PAIRS=${PAIRS:-1 2}

# Comparison and csv generation

BASELINE_MULTUS_UUID=${BASELINE_MULTUS_UUID}
COMPARISON_CONFIG=${COMPARISON_CONFIG:-"uperf-touchstone.json"}
COMPARISON_RC=${COMPARISON_RC:-0}
GEN_CSV=${GEN_CSV:-false}
GEN_JSON=${GEN_JSON:-false}
export SORT_BY_VALUE=${SORT_BY_VALUE:-false}
if [[ -v TOLERANCY_RULES_CFG ]]; then
  TOLERANCY_RULES=${TOLERANCY_RULES_CFG}
else
  TOLERANCY_RULES=${PWD}/uperf-tolerancy-rules.yaml
fi

GSHEET_KEY_LOCATION=${GSHEET_KEY_LOCATION}
EMAIL_ID_FOR_RESULTS_SHEET=${EMAIL_ID_FOR_RESULTS_SHEET}
