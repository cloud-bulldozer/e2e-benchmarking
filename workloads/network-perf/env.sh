# Common

CERBERUS_URL=""
TEST_CLEANUP=${TEST_CLEANUP:-true}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export METADATA_COLLECTION=${METADATA_COLLECTION:-true}
export METADATA_TARGETED=${METADATA_TARGETED:-true}

# Benchark-operator
OPERATOR_REPO=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
OPERATOR_BRANCH=${OPERATOR_BRANCH:-master}

# Workload
export WORKLOAD=${WORKLOAD:-smoke}
export NETWORK_POLICY=${NETWORK_POLICY:=false}
export MULTI_AZ=${MULTI_AZ:=true}
export HOSTNETWORK=false
export SERVICETYPE=clusterip
export ADDRESSPOOL=addresspool-l2
export SERVICE_ETP=Cluster
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}
export SAMPLES=${SAMPLES:-3}
export PAIRS=${PAIRS:-1 2 4}

# Comparison and csv generation

BASELINE_MULTUS_UUID=${BASELINE_MULTUS_UUID}
ES_SERVER_BASELINE=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
COMPARISON_CONFIG=${COMPARISON_CONFIG:-${PWD}/uperf-touchstone.json}
COMPARISON_RC=${COMPARISON_RC:-0}
if [[ -v TOLERANCY_RULES_CFG ]]; then
  TOLERANCY_RULES=${TOLERANCY_RULES_CFG}
else
  TOLERANCY_RULES=${PWD}/uperf-tolerancy-rules.yaml
fi

GSHEET_KEY_LOCATION=${GSHEET_KEY_LOCATION}
EMAIL_ID_FOR_RESULTS_SHEET=${EMAIL_ID_FOR_RESULTS_SHEET}
