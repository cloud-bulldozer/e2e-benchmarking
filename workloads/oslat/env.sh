export ES_SERVER=
export METADATA_COLLECTION=true
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
# oslat specific variables
export RUNTIME=${RUNTIME:-2m}
export DISABLE_CPU_BALANCE=${DISABLE_CPU_BALANCE:-true} 
export USE_TASKSET=${USE_TASKSET:-true}
export MEMORY_REQUESTS=${MEMORY_REQUESTS:-200Mi}
export CPU_REQUESTS=${CPU_REQUESTS:-4}
export MEMORY_LIMITS=${MEMORY_LIMITS:-200Mi}
export CPU_LIMITS=${CPU_LIMITS:-4}
export NODE_COUNT=${NODE_COUNT:-2}
# general options
export TEST_TIMEOUT=${TEST_TIMEOUT:-600}
export TEST_CLEANUP=${TEST_CLEANUP:-"true"}
export PROFILE_TIMEOUT=${PROFILE_TIMEOUT:-40}
