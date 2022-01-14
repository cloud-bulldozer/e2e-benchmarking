# NETOBSERV Performance Scripts
The purpose of scripts in this directory to enable or disable features of [network-observability](https://github.com/netobserv/network-observability-operator). 

Currently, the perf tests are using uperf workload to drive load across the OpenShift Cluster.

There are 3 types network tests that are identified for network-observability
1. pod to pod using Hostnetwork
2. pod to pod using Service
3. pod to pod using Multus (NetworkAttachmentDefinition needs to be provided)

Depending upon, which variant of network tests you want to run, `run_netobserv_perf_comparison_tests.sh` will call respective variant of [networking test](https://github.com/cloud-bulldozer/e2e-benchmarking/tree/master/workloads/network-perf)

For more information on the workloads and it's configuration parameters, [read on](https://github.com/cloud-bulldozer/e2e-benchmarking/blob/master/workloads/network-perf/README.md)