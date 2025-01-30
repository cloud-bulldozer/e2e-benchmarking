# Network Scripts v2

The purpose of the network scripts is to run netperf workload on the Openshift Cluster.

There are 4 types of network tests k8s-netperf will run through:

1. Pod to Pod using SDN
2. Pod to Pod using HostNetwork
3. Pod to Service
4. Pod to External Server provided by the user

Running from CLI:

```sh
$ ./run.sh
```
This will orchestrate the smoke test, to confirm connectivity, and that the benchmark can 
execute against the cloud.

```sh
$ WORKLOAD=full-run.yaml ./run.sh
```
This will orchestrate multiple netwok performance tests. 

| Test | Iterations | Duration | 
|------|------------|----------|
|TCP Stream| 3| 30 |
|UDP Stream| 3| 30 |
|TCP RR| 3| 30 |
|TCP CRR| 3| 10 |

### Environment Variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| ALL_SCENARIOS | Run all test scenarios (hostNetwork & podNetwork) | true |
| CLEAN_UP | Clean-up resources created by k8s-netperf | true |
| DEBUG | Enable debug log levevl for k8s-netperf | true |
| ES_SERVER | Server to send results | `None` (Please set your own that resembles https://USER:PASSWORD@HOSTNAME:443) |
| LOCAL | Run network performance test pods on the same node | false |
| METRICS | Enable collection of metrics by k8s-netperf | true |
| NETPERF_URL | URL to download k8s-netperf | https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz |
| NETPERF_VERSION | k8s-netperf tag/version | v0.1.20 |
| OS | System to run k8s-netperf | Linux |
| PROMETHEUS_URL | URL for external Prometheus | unset |
| TEST_TIMEOUT | Timeout for k8s-netperf | 14400 |
| TOLERANCE | Tolerance when comparing hostNetwork to podNetwork | 70 |
| UUID | UUID which will be used for the workload | uuidgen |
| WORKLOAD | Config definition for k8s-netperf | smoke.yaml |
| EXTERNAL_SERVER_ADDRESS | IP address where the external server is running. User has to configure the external server with the required k8s-netperf driver | unset |
