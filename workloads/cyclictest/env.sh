# Benchmark-operator
export OPERATOR_REPO=${OPERATOR_REPO:-https://github.com/cloud-bulldozer/benchmark-operator.git}
export OPERATOR_BRANCH=${OPERATOR_BRANCH:-master}

# Benchmark comparison
export COMPARE=${COMPARE:-false}
export COMPARE_WITH_GOLD=${COMPARE_WITH_GOLD:-false}

# indexing variables
export ES_SERVER=${ES_SERVER:-https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443}
export ES_INDEX=${ES_INDEX:-ripsaw-cyclictest}
export METADATA_COLLECTION=${METADATA_COLLECTION:-false}

export COMPARE=false
export COMPARE_WITH_GOLD=
export GOLD_SDN=
export GOLD_OCP_VERSION=
export ES_GOLD=
export BASELINE_CLOUD_NAME=
export ES_SERVER_BASELINE=
#export CERBERUS_URL=http://1.2.3.4:8080
#export GSHEET_KEY_LOCATION=
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key

# cyclictest specific variables
export DURATION=${DURATION:-2m}
export DISABLE_CPU_BALANCE=${DISABLE_CPU_BALANCE:-true}
export STRESSNG=${STRESSNG:-false}
export MEMORY_REQUESTS=${MEMORY_REQUESTS:-200Mi}
export CPU_REQUESTS=${CPU_REQUESTS:-4}
export MEMORY_LIMITS=${MEMORY_LIMITS:-400Mi}
export CPU_LIMITS=${CPU_LIMITS:-4}
export TEST_TIMEOUT=${TEST_TIMEOUT:-600}

# general options
export TEST_CLEANUP=${TEST_CLEANUP:-"true"}
export PROFILE_TIMEOUT=${PROFILE_TIMEOUT:-40}

