# Kube-burner e2e benchmarks

The purpose of these scripts is to run a kube-burner workload steered by ripsaw. There are 3 types of workloads at the moment:

- cluster-density
- kubelet-density
- kubelet-density-heavy

## Environment variables

All scripts can be tweaked with the following environment variables:

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **QPS**              | Queries/sec                     | 10      |
| **Burst**            | Burst queries                   | 10      |
| **ES_SERVER**        | Elastic search endpoint         | https://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com|
| **ES_PORT**          | Elastic search port             | 443|
| **ES_INDEX**         | Elastic search index            | ripsaw-kube-burner|
| **PROM_URL**         | Elastic search endpoint         | https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091|
| **JOB_TIMEOUT**      | kube-burner's job timeout       | 7200|
| **WORKLOAD_NODE**    | Workload node name              | "" (don't pin kube-burner to any server)|
| **CERBERUS_URL**     | URL to check the health of the cluster using [Cerberus](https://github.com/openshift-scale/cerberus) | "" (don't check)|

### cluster-density variables

The `cluster-density` workload supports the environment variable **JOB_ITERATIONS**. This variable configures the number of cluster-density jobs iterations to perform (1 namespace per iteration). By default 1000
Each iteration of this workload creates the following objects:

- 12 imagestreams
- 3 buidconfigs
- 6 builds
- 1 deployment with 2 pod replicas (sleep) mounting two secrets each. deployment-2pod
- 2 deployments with 1 pod replicas (sleep) mounting two secrets. deployment-1pod
- 3 services, one pointing to deployment-2pod, and other two pointing to deployment-1pod
- 3 route. 1 pointing to the service deployment-2pod and other two pointing to deployment-1pod
- 20 secrets


### kubelet-density and kubelet-density-heavy variables

The `kubelet-density` and `kubelet-density-heavy` workloads support the following environent variables:

- **NODE_COUNT**: Number of worker nodes to deploy the pods on. During the workload nodes will be labeled with `kubelet-density=true`. Defaults to 4.
- **PODS_PER_NODE**: Define the maximum number of pods to deploy on each labeled node. Defaults to 250

### Configuration file

An [env.sh](env.sh) file is provided with all available configuration parameters.

