# Benchmark comparison
export ES_INDEX=${ES_INDEX:-ripsaw-testpmd}
export METADATA_COLLECTION={METADATA_COLLECTION:-true}

export COMPARE=false
export COMPARE_WITH_GOLD=
export GOLD_SDN=
export GOLD_OCP_VERSION=
export ES_GOLD=
export BASELINE_CLOUD_NAME=
#export CERBERUS_URL=http://1.2.3.4:8080
#export GSHEET_KEY_LOCATION=
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key

# testpmd specific variables
export NODE_COUNT=${NODE_COUNT:-2}
export PRIVILEGED=${PRIVILEGED:-true}
export PIN=${PIN:-true}
export PIN_TESTPMD=${PIN_TESTPMD:-worker-0}
export PIN_TREX=${PIN_TREX:-worker-1}
export MEMORY_CHANNELS=${MEMORY_CHANNELS:-4}
export FORWARDING_CORES=${FORWARDING_CORES:-4}
export RX_QUEUES=${RX_QUEUES:-1}
export TX_QUEUES=${TX_QUEUES:-1}
export RX_DESCRIPTORS=${RX_DESCRIPTORS:-1024}
export TX_DESCRIPTORS=${TX_DESCRIPTORS:-1024}
export FORWARD_MODE=${FORWARD_MODE:-"mac"}
export STATS_PERIOD=${STATS_PERIOD:-1}
export DISABLE_RSS=${DISABLE_RSS:-"true"}
export DURATION=${DURATION:-30}
export PACKET_SIZE=${PACKET_SIZE:-64}
export PACKET_RATE=${PACKET_RATE:-"10kpps"}
export NUM_STREAM=${NUM_STREAM:-1}
export NETWORK_NAME=${NETWORK_NAME:-testpmd-sriov-network}
export TESTPMD_NETWORK_COUNT=${TESTPMD_NETWORK_COUNT:-2}
export TREX_NETWORK_COUNT=${TREX_NETWORK_COUNT:-2}
export PROFILE_TIMEOUT=${PROFILE_TIMEOUT:-40}

# general options 
export TEST_TIMEOUT=${TEST_TIMEOUT:-600}
export TEST_CLEANUP=${TEST_CLEANUP:-"true"}

