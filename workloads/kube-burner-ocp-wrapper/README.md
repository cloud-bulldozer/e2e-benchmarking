# Kube-burner

The `./run.sh` script is just a small wrapper on top of kube-burner to be used as entrypoint of some of its flags. The supported workloads are described in the [kube-burner OCP wrapper docs](https://kube-burner.github.io/kube-burner-ocp/latest/).

In order to run a workload you have to set the `WORKLOAD` environment variable to one of the workloads supported by kube-burner. Example

```shell
$ ITERATIONS=5 WORKLOAD=cluster-density-v2 ./run.sh 
/tmp/kube-burner-ocp cluster-density-v2 --log-level=info --iterations=5 --churn=true --es-server=https://USER:PASSWORD@HOSTNAME:443 --es-index=ripsaw-kube-burner --qps=20 --burst=20
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

Or change the deletion strategy during churn. It is recommended for churning on large(500) scale clusters to maintain moderate kube-api burst.

```shell
$ EXTRA_FLAGS="--churn-deletion-strategy=gvr" ITERATIONS=5000 WORKLOAD=cluster-density-v2 ./run.sh
```

### Cluster-density and cluster-density-v2

- **ITERATIONS**: Defines the number of iterations of the workload to run. No default value
- **CHURN**: Enables workload churning. Workload churning is enabled by default with `churn-duration=1h`, `churn-delay=2m` and `churn-percent=10`. These parameters can be tuned through the `EXTRA_FLAGS` variable as noted previously.

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

