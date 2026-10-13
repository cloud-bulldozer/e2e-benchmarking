# Kube-burner

The `./run.sh` script is just a small wrapper on top of kube-burner to be used as entrypoint of some of its flags. The supported workloads are described in the [kube-burner OCP wrapper docs](https://kube-burner.github.io/kube-burner-ocp/latest/).

In order to run a workload you have to set the `WORKLOAD` environment variable to one of the workloads supported by kube-burner. Example

```shell
$ ITERATIONS=5 WORKLOAD=cluster-density-v2 ./run.sh 
/tmp/kube-burner-ocp cluster-density-v2 --log-level=info --iterations=5 --es-server=https://USER:PASSWORD@HOSTNAME:443 --es-index=ripsaw-kube-burner --qps=20 --burst=20
INFO[2023-03-13 16:39:57] 📁 Creating indexer: elastic                  
INFO[2023-03-13 16:39:59] 👽 Initializing prometheus client with URL: <truncated>
INFO[2023-03-13 16:40:00] 🔔 Initializing alert manager for prometheus: <truncated>
INFO[2023-03-13 16:40:00] 🔥 Starting kube-burner (1.4.3@a575df584a6b520a45e2fe7903e608a34e722e5f) with UUID 69022407-7c55-4b8a-add2-5e40e6b4c593 
INFO[2023-03-13 16:40:00] 📈 Creating measurement factory               
INFO[2023-03-13 16:40:00] Registered measurement: podLatency           
INFO[2023-03-13 16:40:00] Job cluster-density-v2: 5 iterations with 1 ImageStream replicas 
INFO[2023-03-13 16:40:00] Job cluster-density-v2: 5 iterations with 1 Build replicas 
INFO[2023-03-13 16:40:00] Job cluster-density-v2: 5 iterations with 3 Deployment replicas 
INFO[2023-03-13 16:40:00] Job cluster-density-v2: 5 iterations with 2 Deployment replicas 
<truncated>
```

## Environment variables

This wrapper supports some variables to tweak some basic parameters of the workloads:

- **ES_SERVER**: Defines the ElasticSearch/OpenSearch endpoint. By default it points the development instance. Indexing can be disabled with `export ES_SERVER=""`.
- **ES_INDEX**: Defines the ElasticSearch/OpenSearch index name. By default `ripsaw-kube-burner`
- **QPS** and **BURST**: Defines client-go QPS and BURST parameters for kube-burner. 20 by default
- **GC**: Garbage collect created namespaces. true by default
- **EXTRA_FLAGS**: Extra flags that will be appended to the underlying kube-burner-ocp command, by default empty.
- **KUBE_BURNER_VERSION**: Defines the version of kube-burner-ocp to use. By default kube-burner-ocp is downloaded from the github releases.
- **KUBE_BURNER_URL**: Defines the URL of the kube-burner-ocp binary to use. It has higher precedence than KUBE_BURNER_VERSION.

### Using the EXTRA_FLAGS variable

All the flags that can be appeneded through the `EXTRA_FLAGS` variable can be found in the [kube-burner-ocp docs](https://kube-burner.github.io/kube-burner-ocp/latest/)
For example, we can tweak the churning behaviour of the cluster-density workload with:

```shell
$ export EXTRA_FLAGS="--churn-duration=1d --churn-percent=5 --churn-delay=5m"
$ ITERATIONS=500 WORKLOAD=cluster-density-v2 ./run.sh
```

Or increase the benchmark timeout (by default 3h):

```shell
$ EXTRA_FLAGS="--timeout=5h" ITERATIONS=500 WORKLOAD=cluster-density-v2 ./run.sh
```

Or change the churn mode. It is recommended for churning on large(500) scale clusters to maintain moderate kube-api burst.

```shell
$ EXTRA_FLAGS="--churn-duration=1h --churn-mode=objects" ITERATIONS=5000 WORKLOAD=cluster-density-v2 ./run.sh
```

### Cluster-density and cluster-density-v2

- **ITERATIONS**: Defines the number of iterations of the workload to run. No default value

## MicroShift node-density workloads

MicroShift node-density workloads can be run through the same generic
`run.sh` wrapper by passing the workload name and kube-burner-ocp flags through
environment variables:

- `node-density`
- `node-density-cni`
- `node-density-cni-netpol`, run through the kube-burner-ocp
  `network-policy` workload

MicroShift does not expose the OpenShift in-cluster Prometheus route, so pass
an external Prometheus endpoint with `--prometheus-url`. For indexed runs, set
`ES_SERVER` and `ES_INDEX` as usual. For automation that needs a specific
kube-burner-ocp build, use `KUBE_BURNER_VERSION` or `KUBE_BURNER_URL`.
MicroShift support requires kube-burner-ocp v1.11.17 or later.

Run `node-density`:

```shell
$ ES_SERVER=https://USER:PASSWORD@HOSTNAME:443 \
  KUBE_BURNER_VERSION=1.11.17 \
  WORKLOAD=node-density \
  QPS=10 \
  BURST=10 \
  EXTRA_FLAGS="--pods-per-node=245 --selector=node-role.kubernetes.io/worker=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= --metrics-profile=microshift-metrics.yml --prometheus-url=http://prometheus.example:9091 --alerting=false" \
  ./run.sh
```

Run `node-density-cni`:

```shell
$ ES_SERVER=https://USER:PASSWORD@HOSTNAME:443 \
  KUBE_BURNER_VERSION=1.11.17 \
  WORKLOAD=node-density-cni \
  QPS=10 \
  BURST=10 \
  EXTRA_FLAGS="--pods-per-node=245 --selector=node-role.kubernetes.io/worker=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= --metrics-profile=microshift-metrics.yml --prometheus-url=http://prometheus.example:9091 --alerting=false" \
  ./run.sh
```

Run the network policy variant:

```shell
$ ES_SERVER=https://USER:PASSWORD@HOSTNAME:443 \
  KUBE_BURNER_VERSION=1.11.17 \
  WORKLOAD=network-policy \
  ITERATIONS=75 \
  QPS=10 \
  BURST=10 \
  EXTRA_FLAGS="--metrics-profile=microshift-metrics.yml --prometheus-url=http://prometheus.example:9091 --alerting=false" \
  ./run.sh
```

### QPS sweeps

Set `QPS_LIST` to an ordered, whitespace-separated list of distinct positive
integers to enable a sweep. An explicit list allows both regular and sparse
sampling without start/end/step rules. Unset or empty keeps the single-run
behavior, including its UUID, exit status and artifact paths.

- `UUID`: base run ID (generated when unset); each step uses `${UUID}-qps${QPS}`.
  Use a new base UUID for each workload and iteration. Step UUIDs must fit the
  Kubernetes label limit of 63 characters.
- `BURST`: follows each step's QPS when unset; an explicit positive integer stays
  fixed across the sweep. `QPS` is ignored in sweep mode.
- `SWEEP_SLEEP`: seconds between steps **after namespace deletion**, default `30`;
  set `0` to disable.
- `SWEEP_CLEANUP_TIMEOUT`: namespace deletion timeout in seconds, default `300`.
  Cleanup uses `oc delete namespaces` with the step's `kube-burner.io/uuid` label,
  waits for deletion, and has a 10-second API request timeout and an outer wall
  timeout (plus up to 5 seconds to kill an unresponsive client).

Each step calls the existing wrapper, including its binary download and indexing.
`EXTRA_FLAGS`, `ES_SERVER`, `ES_INDEX`, `--local-indexing` and `--metrics-endpoint`
are passed through unchanged. Keep the default local directory
`collected-metrics-<step-uuid>`, or use UUID-dependent paths in custom endpoint
configuration; a fixed custom metrics directory would overwrite earlier steps.
Do not override `--uuid`, `--qps` or `--burst` through `EXTRA_FLAGS`.
Relative metrics-profile/endpoint paths still resolve from the current directory.

For example, run the MicroShift node-density QPS 2..20 sweep with 245 pods/node:

```shell
$ unset BURST
$ WORKLOAD=node-density UUID=$(uuidgen) QPS_LIST="2 4 6 8 10 12 14 16 18 20" \
  EXTRA_FLAGS="--pods-per-node=245 --local-indexing --metrics-endpoint=microshift-endpoint.yml --alerting=false" \
  ./run.sh
```

Use `WORKLOAD=node-density-cni` and a new UUID for the second workload. Configure
`microshift-endpoint.yml` with the external Prometheus endpoint, MicroShift metrics
profile and a **5s step** so short jobs have enough samples. For local archival:

```yaml
- endpoint: http://prometheus.example:9091
  step: 5s
  metrics:
    - microshift-metrics.yml
  indexer:
    type: local
```

Endpoint/indexer configuration remains kube-burner-ocp's responsibility; sweep
mode does not alter it or verify metric completeness. For ES plus local output,
use the same endpoint configuration as a single run.

The sweep stops at the first failed invocation or cleanup, exits nonzero and
never retries. Namespace cleanup also runs on exit/INT/TERM, even with `GC=false`.
It targets only the current step's namespaces, not unrelated runs or cluster-wide
resources. Index-only workloads are not supported. Sweep mode needs `jq`, `oc`,
GNU `timeout` and `setsid` in addition to the single-run dependencies.

Artifacts in the current directory:

- `sweep-<step-uuid>.log`: each invocation's stdout/stderr and cleanup output.
- `collected-metrics-<step-uuid>/`: normal kube-burner local output when enabled.
- `sweep-<base-uuid>.json`: an array atomically updated after every attempted step,
  containing `workload`, `qps`, `burst`, `uuid`, `start_epoch`, `end_epoch`, `rc`,
  `cleanup_rc`, and `log`. Epochs are integer seconds and include cleanup time.
  `rc` is the wrapper exit code (130/143 for INT/TERM); `cleanup_rc` is separate.
  Unattempted steps are absent. Existing summaries or default step artifacts are
  rejected to avoid mixing runs.

CI consumers opting into sweeps must archive the summary, logs and every step's
metrics directory. Existing single-run consumers need no change.

Local tests (all cluster clients and downloads stubbed):

```shell
python3 workloads/kube-burner-ocp-wrapper/test-sweep.py
shellcheck workloads/kube-burner-ocp-wrapper/sweep.sh
```

## HyperShift

It's possible to use this script with HyperShift hosted clusters. The particularity of this is that kube-burner-ocp will grab metrics from different Prometheus endpoints:

- Hosted control-plane stack or OBO: Hosted control-plane application metrics such as etcd, API latencies, etc.
- Management cluster stack: Hardware utilization metrics from its worker nodes and hosted control-plane pods.
- Hosted cluster stack: From this endpoint kube-burner-ocp collects data-plane metrics.

In order to use it, the hosted cluster kubeconfig must be set upfront. These environment variables are also required:

- **MC_KUBECONFIG**: This variable points to the valid management cluster kubeconfig

### ARO inputs

Along with above environmental inputs, ARO MC needs few more inputs from the users. 
We are required to scrape metrics from multiple enpoints like ROSA, users need to supply those endpoints and tokens

- **AZURE_PROM**: Azure Managed Prometheus instance endpoint for Management cluster metrics
- **AZURE_PROM_TOKEN**: Token for the same
- **AKS_PROM**: Prometheus Operator endpoint deployed on the MC to scrape HCP metrics

The AKS Cluster observability is not finalized so this approach is subjected to change in the future when ARO-HCP is GA.

## EgressIP

EgressIP testing requires a nginx server outside OCP cluster. This server should be in the same network CIDR as OCP nodes but not controlled by OVN SDN. Workload client pods send requests to this external nginx server. Currently, we support egressIP testing only on the AWS platform. We aim to extend this support to other platforms and bare-metal environments. This script creates AWS instance and spawns external nginx servers.

```shell
$ EXTRA_FLAGS="--addresses-per-iteration=1" AWS_ACCESS_KEY_ID="" AWS_SECRET_ACCESS_KEY="" ITERATIONS=1 WORKLOAD=egressip ./run.sh
```
