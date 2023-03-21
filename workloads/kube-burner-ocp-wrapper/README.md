# Kube-burner

The `./run.sh` script is just a small wrapper on top of kube-burner to be used as entrypoint of some of its flags. The supported workloads are described in the [OpenShift OCP wrapper section](https://kube-burner.readthedocs.io/en/latest/ocp/) of the kube-burner docs.

In order to run a workload you have to set the `WORKLOAD` environment variable to one of the workloads supported by kube-burner. Example

```shell
$ ITERATIONS=5 WORKLOAD=cluster-density-v2 ./run.sh 
/tmp/kube-burner ocp cluster-density-v2 --log-level=info --iterations=5 --churn=true --es-server=https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com --es-index=ripsaw-kube-burner --qps=20 --burst=20
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

- **ES_SERVER**: Defines the ElasticSearch/OpenSearch endpoint. By default it points the development instance.
- **ES_INDEX**: Defines the ElasticSearch/OpenSearch index name. By default `ripsaw-kube-burner`
- **QPS** and **BURST**: Defines client-go QPS and BURST parameters for kube-burner. 20 by default
- **GC**: Garbage collect created namespaces. true by default
- **EXTRA_FLAGS**: Extra flags that will be appended to the underlying kube-burner ocp command, by default empty.

### Cluster-density and cluster-density-v2

- **ITERATIONS**: Defines the number of iterations of the workload to run. No default value
- **CHURN**: Enables workload churning. By default is true

## HyperShift

It's possible to use this script with HyperShift hosted clusters. The particularity of this is that kube-burner will grab metrics from different Prometheus endpoints:

- Hosted control-plane stack or OBO: Hosted control-plane application metrics such as etcd, API latencies, etc.
- Management cluster stack: Hardware utilization metrics from its worker nodes and hosted control-plane pods.
- Hosted cluster stack: From this endpoint kube-burner collects data-plane metrics.

In order to use it, the hosted cluster kubeconfig must be set upfront. These environment variables are also required:

- **MC_KUBECONFIG**: This variable points to the valid management cluster kubeconfig
