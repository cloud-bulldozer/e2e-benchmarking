
source ../../utils/common.sh
source ./netobserv_common.sh

NETWORK_VARIANT=$1

if [[ -z $NETWORK_VARIANT ]]; then
    echo "must pass networking variant as argument"
    exit 1
fi 

log "running performance test for $NETWORK_VARIANT"
run_perf_test_w_netobserv
if [[ $NETWORK_VARIANT == "POD_NETWORK" ]]; then
    source ../network-perf/run_pod_network_test_fromgit.sh
    run_perf_test_wo_netobserv
    source ../network-perf/run_pod_network_test_fromgit.sh
elif [[ $NETWORK_VARIANT == "SERVICEIP_NETWORK" ]]; then
    echo $1
    source ../network-perf/run_serviceip_network_test_fromgit.sh
    run_perf_test_wo_netobserv
    source ../network-perf/run_serviceip_network_test_fromgit.sh
elif [[ $NETWORK_VARIANT == "MULTUS_NETWORK" ]]; then
    source ../network-perf/run_multus_network_tests_fromgit.sh
    run_perf_test_wo_netobserv
    source ../network-perf/run_multus_network_tests_fromgit.sh
else
    echo "unsupported network variant for network-observability"
    exit 1
fi