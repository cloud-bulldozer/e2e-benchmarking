# Network Scripts v2

The purpose of the network scripts is to run netperf workload on the Openshift Cluster.

There are 3 types of network tests k8s-netperf will run through:

1. Pod to Pod using SDN
3. Pod to Pod using HostNetwork 
4. Pod to Service 

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
| ES_SERVER | Server to send results | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443 |
| UUID | UUID which will be used for the workload | uuidgen |
| VERSION | k8s-netperf tag/version | v0.1.13 |
| OS | System to run k8s-netperf | Linux |
| NETPERF_URL | URL to download k8s-netperf | https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz |
| WORKLOAD | Config definition for k8s-netperf | smoke.yaml |
| TEST_TIMEOUT | Timeout for k8s-netperf | 7200 |
| TOLERANCE | Tolerance when comparing hostNetwork to podNetwork | 70 |
