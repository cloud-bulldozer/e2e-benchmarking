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

When `PLATFORM=microshift`, `LOCAL` defaults to `true` and `METRICS` defaults to `false` because MicroShift has no in-cluster Prometheus. On one MicroShift cluster `LOCAL=true` is required: `run.sh` exits immediately if `PLATFORM=microshift` is set with `LOCAL=false`, unless `SERVER_KUBECONFIG` selects a cross-cluster run (below). To collect metrics on MicroShift, set `METRICS=true` and point `PROMETHEUS_URL` at an external Prometheus.

## Cross-cluster

Setting `SERVER_KUBECONFIG` runs the client pods on the cluster of `KUBECONFIG` and the server pods on the cluster of `SERVER_KUBECONFIG`, for example two MicroShift clusters connected with Cluster-to-Cluster Connectivity (C2CC). It needs a k8s-netperf release with cross-cluster mode (`--server-kubeconfig`).

```sh
$ KUBECONFIG=~/.kube/cluster-a PLATFORM=microshift \
  SERVER_KUBECONFIG=~/.kube/cluster-b SERVER_DOMAIN=cluster-b.remote \
  WORKLOAD=full-run.yaml ./run.sh
```

- `SERVER_DOMAIN` is the DNS suffix the client cluster uses for the server cluster's Services; `service: true` entries of the workload connect to `<service>.netperf.svc.<SERVER_DOMAIN>` and need it.
- `SERVER_PROMETHEUS_URL` is the server cluster's Prometheus, for server-side metrics (redacted in the printed command).
- `LOCAL` defaults to `false` in this mode, also on MicroShift. `run.sh` passes neither `--local` nor `--all`, so `ALL_SCENARIOS` has no effect (host network tests are not supported across clusters), and it labels no node.
- `run.sh` stops before anything runs when `SERVER_KUBECONFIG` is combined with `LOCAL=true` or `EXTERNAL_SERVER_ADDRESS`, when it is not a readable file, or when `SERVER_DOMAIN` or `SERVER_PROMETHEUS_URL` is set without it. k8s-netperf itself rejects the other modes it does not support across clusters (VMs, UDN, bridge, localnet, `POD=false`) before it creates anything.
- The debug output after the run also shows the server cluster's pods and nodes.

## Node labels

When client and server run on two nodes of one cluster (`LOCAL=false` without `SERVER_KUBECONFIG`), `run.sh` labels the first two non-infra workers `netperf=client` and `netperf=server`, and k8s-netperf prefers those nodes. `run.sh` removes only the labels this run added, and only if nobody changed or took them over since. A label that was there before the run stays, as does one whose outcome is unknown (for example a label call that timed out) or one left by an interrupted earlier run. Remove those by hand: `kubectl label nodes <node> netperf-`. If a chosen node already carries a different `netperf` value, the run stops before changing anything. Other nodes with a `netperf` label are named in a warning, because k8s-netperf may place pods on them.

Same-node runs (`LOCAL=true`) and cross-cluster runs add and remove no `netperf` label. On OpenShift, `LOCAL=true` still removes the infra role label from infra nodes, as before.

## When a run fails

| Outcome | Label removal | Debug queries | `*.csv` printed | Indexing (`utils/index.sh`) | Exit status |
|---|---|---|---|---|---|
| k8s-netperf succeeds | yes | yes | yes | yes | 0 |
| k8s-netperf fails or times out, `CLEAN_UP=true` | yes | yes | yes | yes | k8s-netperf's (124 on `TEST_TIMEOUT`) |
| k8s-netperf fails or times out, `CLEAN_UP=false` | no | no | yes | no | k8s-netperf's |

With `CLEAN_UP=false` the caller owns cleanup, so after a failed run `run.sh` makes no further call to either cluster, whatever CI variables (`PROW_JOB_ID`, `BUILD_ID`, `AIRFLOW_CTX_DAG_ID`) are set.

## Tests

`python3 workloads/network-perf-v2/test-run.py` runs `run.sh` against fake `oc`, `kubectl`, `curl` and k8s-netperf; it needs no cluster.

## VM bridge and localnet

These modes run VMs only (`--vm --pod=false`). Equivalent k8s-netperf invocations:

Bridge (requires virtctl):

```sh
# k8s-netperf --pod=false --vm --bridge br0 --bridgeNetwork bridgeNetwork.json --use-virtctl
$ VM=true POD=false BRIDGE=br0 BRIDGE_CONFIG=bridgeNetwork.json USE_VIRTCTL=true ./run.sh
```

Localnet (creates a CUDN from the named localnet; VM IPs from the JSON config):

```sh
# k8s-netperf --localnet physnet --localnet-config localnetNetwork.json --vm --pod=false
$ VM=true POD=false LOCALNET=physnet LOCALNET_CONFIG=localnetNetwork.json ./run.sh
```

```sh
$ NETPERF_VERSION=main VM=true POD=false LOCALNET=physnet LOCALNET_CONFIG=localnetNetwork.json USE_VIRTCTL=true ALL_SCENARIOS=false ./run.sh
```

## Environment Variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| ALL_SCENARIOS | Run all test scenarios (hostNetwork & podNetwork) | true |
| BRIDGE | Bridge NAD name passed as `--bridge` | unset |
| BRIDGE_CONFIG | Path to bridge VM IP JSON → `--bridgeNetwork` (e.g. `bridgeNetwork.json`) | unset |
| CLEAN_UP | Clean-up resources created by k8s-netperf. With `false`, a failed run is followed by no cluster call | true |
| DEBUG | Enable debug log level for k8s-netperf | true |
| ES_SERVER | Server to send results | `None` (Please set your own that resembles https://USER:PASSWORD@HOSTNAME:443) |
| EXTERNAL_SERVER_ADDRESS | IP address where the external server is running. User has to configure the external server with the required k8s-netperf driver | unset |
| LOCAL | Run network performance test pods on the same node | `true` when `PLATFORM=microshift` without `SERVER_KUBECONFIG`, otherwise `false` |
| LOCALNET | Localnet network name → `--localnet` (used by k8s-netperf to create the CUDN) | unset |
| LOCALNET_CONFIG | Path to localnet VM IP JSON → `--localnet-config` (e.g. `localnetNetwork.json`) | unset |
| METRICS | Enable collection of metrics by k8s-netperf | `false` when `PLATFORM=microshift`, otherwise `true` |
| NETPERF_FILENAME | Filename of the k8s-netperf binary that run.sh executes | k8s-netperf |
| NETPERF_URL | URL to download k8s-netperf | https://github.com/cloud-bulldozer/k8s-netperf/releases/download/${NETPERF_VERSION}/k8s-netperf_${OS}_${NETPERF_VERSION}_${ARCH}.tar.gz |
| NETPERF_VERSION | k8s-netperf tag/version | v0.1.43 |
| OS | System to run k8s-netperf | Linux |
| PLATFORM | Target platform (`openshift` or `microshift`) | openshift |
| POD | Run pod-network scenarios | true |
| PROMETHEUS_URL | URL for external Prometheus | unset |
| SERVER_DOMAIN | Cross-cluster: DNS suffix of the server cluster's Services → `--server-domain` | unset |
| SERVER_KUBECONFIG | Cross-cluster: kubeconfig of the server cluster → `--server-kubeconfig`; setting it turns cross-cluster mode on | unset |
| SERVER_PROMETHEUS_URL | Cross-cluster: Prometheus of the server cluster → `--server-prom` | unset |
| TEST_TIMEOUT | Timeout for k8s-netperf | 14400 |
| TOLERANCE | Tolerance when comparing hostNetwork to podNetwork | 70 |
| UDNL2 | Run User-Defined Network (L2) scenarios | false |
| UDNL3 | Run User-Defined Network (L3) scenarios | false |
| USE_VIRTCTL | When `VM=true`, pass `--use-virtctl` to k8s-netperf so it uses `virtctl` to interact with the VMs | unset |
| UUID | UUID which will be used for the workload | uuidgen |
| VM | Run scenarios using KubeVirt VMs | false |
| WORKLOAD | Config definition for k8s-netperf | smoke.yaml |
| WORKLOAD_NAME | Workload name passed to indexing as the `WORKLOAD` field | k8s-netperf |
