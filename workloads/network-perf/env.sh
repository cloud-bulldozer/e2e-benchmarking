# Common
TEST_CLEANUP=${TEST_CLEANUP:-true}
export UUID=${UUID:-$(uuidgen)}
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export METADATA_COLLECTION=${METADATA_COLLECTION:-true}
export METADATA_TARGETED=${METADATA_TARGETED:-true}

# Benchark-operator
export OPERATOR_REPO=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
export OPERATOR_BRANCH=${OPERATOR_BRANCH:-master}

# Benchmark-comparison
export COMPARE=${COMPARE:-false}
export COMPARE_WITH_GOLD=${COMPARE_WITH_GOLD:-false}
export BASELINE_HOSTNET_UUID=
export BASELINE_POD_1P_UUID=
export BASELINE_POD_2P_UUID=
export BASELINE_POD_4P_UUID=
export BASELINE_SVC_1P_UUID=
export BASELINE_SVC_2P_UUID=
export BASELINE_SVC_4P_UUID=
export BASELINE_MULTUS_UUID=
export THROUGHPUT_TOLERANCE=10
export LATENCY_TOLERANCE=10
CERBERUS_URL=
#export GSHEET_KEY_LOCATION=
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key
THROUGHPUT_TOLERANCE=${THROUGHPUT_TOLERANCE:=10}
LATENCY_TOLERANCE=${LATENCY_TOLERANCE:=10}
export GOLD_SDN=${GOLD_SDN:-openshiftsdn}
export GOLD_OCP_VERSION=${GOLD_OCP_VERSION}
export ES_GOLD=${ES_GOLD}
export BASELINE_CLOUD_NAME=${BASELINE_CLOUD_NAME}
export ES_SERVER_BASELINE=${ES_SERVER_BASELINE:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}

# Workload
export NETWORK_POLICY=${NETWORK_POLICY:=false}
export MULTI_AZ=${MULTI_AZ:=true}
export HOSTNETWORK=false
export SERVICEIP=false
export TEST_TIMEOUT=${TEST_TIMEOUT:-7200}
