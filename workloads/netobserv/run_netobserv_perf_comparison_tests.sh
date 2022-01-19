
source ../../utils/common.sh
source ./netobserv_common.sh

NETWORK_VARIANT=$1

if [[ -z $NETWORK_VARIANT ]]; then
    echo "must pass networking variant as argument"
    exit 1
fi 

log "running performance test for $NETWORK_VARIANT"
RIPSAW_UPERF_PATH=$PWD/ripsaw-uperf-crd.yaml
run_perf_test_w_netobserv
if [[ $NETWORK_VARIANT == "POD_NETWORK" ]]; then
    cd ../network-perf && ./run_pod_network_test_fromgit.sh $RIPSAW_UPERF_PATH
    run_perf_test_wo_netobserv
    cd ../network-perf && ./run_pod_network_test_fromgit.sh $RIPSAW_UPERF_PATH
elif [[ $NETWORK_VARIANT == "SERVICEIP_NETWORK" ]]; then
    cd ../network-perf && ./run_serviceip_network_test_fromgit.sh $RIPSAW_UPERF_PATH
    run_perf_test_wo_netobserv
    cd ../network-perf && ./run_serviceip_network_test_fromgit.sh $RIPSAW_UPERF_PATH
elif [[ $NETWORK_VARIANT == "MULTUS_NETWORK" ]]; then
    cd ../network-perf && run_multus_network_tests_fromgit.sh $RIPSAW_UPERF_PATH
    run_perf_test_wo_netobserv
    cd ../network-perf && run_multus_network_tests_fromgit.sh $RIPSAW_UPERF_PATH
else
    echo "unsupported network variant for network-observability"
    exit 1
fi
cd ../netobserv