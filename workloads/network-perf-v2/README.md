# Network Scripts v2

The purpose of the network scripts is to run the k8s-netperf workload against an OpenShift or MicroShift cluster.

There are 4 types of network tests k8s-netperf will run through:

1. Pod to pod using the cluster pod network
2. Pod to Pod using HostNetwork
3. Pod to Service
4. Pod to External Server provided by the user

Running from CLI:

```sh
$ ./run.sh
```
This will orchestrate the smoke test, to confirm connectivity, and that the benchmark can
execute against the cluster.

```sh
$ WORKLOAD=full-run.yaml ./run.sh
```
This will orchestrate multiple network performance tests.

| Test | Parallelism | MessageSize | Samples | Duration |
|------|-------------|-------------|---------|----------|
| TCP Stream | 1, 2 | 64, 1024, 4096, 8192 | 5 | 30 |
| UDP Stream | 1, 2 | 64, 1024, 4096, 8192 | 5 | 30 |
| TCP RR | 1, 2 | 1024 | 5 | 30 |
| TCP CRR | 1 | 1024 | 5 | 10 |
| TCP Stream (service) | 1 | 64, 1024, 4096, 8192 | 5 | 30 |
| UDP Stream (service) | 1 | 64, 1024, 4096, 8192 | 5 | 30 |
| TCP RR (service) | 1 | 1024 | 5 | 30 |
| TCP CRR (service) | 1 | 1024 | 5 | 10 |

```sh
$ WORKLOAD=ossm.yaml ./run.sh
```
This will orchestrate multiple network performance tests for OpenShift ServiceMesh.

| Test | Parallelism | MessageSize | Samples | Duration |
|------|-------------|-------------|---------|----------|
| TCP Stream | 1, 2, 4 | 64, 1024, 8192 | 2 | 30 |
| TCP RR | 1 | 64, 1024, 8192 | 2 | 30 |

## MicroShift

Set `PLATFORM=microshift` to run against a single-node MicroShift cluster:

```sh
$ PLATFORM=microshift WORKLOAD=full-run.yaml ./run.sh
```

When `PLATFORM=microshift`, `LOCAL` defaults to `true` and `METRICS` defaults to `false` because MicroShift has no in-cluster Prometheus. `LOCAL=true` is a hard requirement on MicroShift today — `run.sh` exits immediately if `PLATFORM=microshift` is set with `LOCAL=false`. To collect metrics on MicroShift, set `METRICS=true` and point `PROMETHEUS_URL` at an external Prometheus.

## Environment Variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| ALL_SCENARIOS | Run all test scenarios (hostNetwork & podNetwork) | true |
| CLEAN_UP | Clean-up resources created by k8s-netperf | true |
| DEBUG | Enable debug log level for k8s-netperf | true |
| ES_SERVER | Server to send results | `None` (Please set your own that resembles https://USER:PASSWORD@HOSTNAME:443) |
| EXTERNAL_SERVER_ADDRESS | IP address where the external server is running. User has to configure the external server with the required k8s-netperf driver | unset |
| LOCAL | Run network performance test pods on the same node | `true` when `PLATFORM=microshift`, otherwise `false` |
| METRICS | Enable collection of metrics by k8s-netperf | `false` when `PLATFORM=microshift`, otherwise `true` |
| NETPERF_FILENAME | Filename of the k8s-netperf binary that run.sh executes | k8s-netperf |
| NETPERF_URL | URL to download k8s-netperf | https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz |
| NETPERF_VERSION | k8s-netperf tag/version | v0.1.41 |
| OS | System to run k8s-netperf | Linux |
| PLATFORM | Target platform (`openshift` or `microshift`) | openshift |
| POD | Run pod-network scenarios | true |
| PROMETHEUS_URL | URL for external Prometheus | unset |
| TEST_TIMEOUT | Timeout for k8s-netperf | 14400 |
| TOLERANCE | Tolerance when comparing hostNetwork to podNetwork | 70 |
| UDNL2 | Run User-Defined Network (L2) scenarios | false |
| UDNL3 | Run User-Defined Network (L3) scenarios | false |
| USE_VIRTCTL | When `VM=true`, pass `--use-virtctl` to k8s-netperf so it uses `virtctl` to interact with the VMs | unset |
| UUID | UUID which will be used for the workload | uuidgen |
| VM | Run scenarios using KubeVirt VMs | false |
| WORKLOAD | Config definition for k8s-netperf | smoke.yaml |
| WORKLOAD_NAME | Workload name passed to indexing as the `WORKLOAD` field | k8s-netperf |
