# Kube-burner e2e benchmarks

The purpose of these scripts is to run a kube-burner workload steered by ripsaw. There are 3 types of workloads at the moment:

- cluster-density
- kubelet-density
- kubelet-density-heavy

## Environment variables

All scripts can be tweaked with the following environment variables:

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **QPS**              | Queries/sec                     | 20      |
| **BURST**            | Burst queries                   | 20      |
| **ES_SERVER**        | Elastic search endpoint         | https://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | Elastic search index            | ripsaw-kube-burner|
| **PROM_URL**         | Prometheus endpoint         | https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091|
| **JOB_TIMEOUT**      | kube-burner's job timeout, in seconds      | 17500 |
| **WORKLOAD_NODE**    | Workload node name              | "" (don't pin kube-burner to any server)|
| **CERBERUS_URL**     | URL to check the health of the cluster using [Cerberus](https://github.com/openshift-scale/cerberus) | "" (don't check)|
| **STEP_SIZE**        | Prometheus step size, useful for long benchmarks | 30s|
| **METRICS_PROFILE**        | Metric profile that indicates what prometheus metrics kube-burner will collect, accepts __metrics.yaml__ or __metrics-aggregated.yaml__ | metrics.yaml for kubelet-density workloads and metrics-aggregated.yaml for cluster-density workloads |
| **METADATA_COLLECTION**    | Enable metadata collection | true |
| **LOG_STREAMING**    | Enable log streaming of kube-burner pod | true |
| **CLEANUP**          | Delete old namespaces for the selected workload before starting benchmark | false |
| **CLEANUP_WHEN_FINISH** | Delete workload's namespaces after running it | false |
| **LOG_LEVEL**        | Kube-burner log level | info |

**Note**: You can use basic authentication for ES indexing using the notation `http(s)://[username]:[password]@[host]:[port]` in **ES_SERVER**.

### cluster-density variables

The `cluster-density` workload supports the environment variable **JOB_ITERATIONS**. This variable configures the number of cluster-density jobs iterations to perform (1 namespace per iteration). By default 1000.

Each iteration creates the following objects:

- 12 imagestreams
- 3 buildconfigs
- 6 builds
- 1 deployment with 2 pod replicas (sleep) mounting two secrets each. deployment-2pod
- 2 deployments with 1 pod replicas (sleep) mounting two secrets. deployment-1pod
- 3 services, one pointing to deployment-2pod, and other two pointing to deployment-1pod
- 3 route. 1 pointing to the service deployment-2pod and other two pointing to deployment-1pod
- 10 secrets. 2 of them mounted by the previous deployments.
- 10 configMaps. 2 of them mounted by the previous deployments.


### kubelet-density and kubelet-density-heavy variables

The `kubelet-density` and `kubelet-density-heavy` workloads support the following environment variables:

- **NODE_COUNT**: Number of worker nodes to deploy the pods on. During the workload nodes will be labeled with `kubelet-density=true`. Defaults to 4.
- **PODS_PER_NODE**: Define the maximum number of pods to deploy on each labeled node. Defaults to 250

These workloads create different objects each:

- **kubelet-density**: Creates a single namespace with a number of Deployments proportional to the calculated number of pod.
Each iteration of this workload creates the following object:
  - 1 pod. (sleep)


- **kubelet-density-heavy**. Creates a **single namespace with a number of applications proportional to the calculated number of pods / 2**. This application consists on two deployments (a postgresql database and a simple client that generates some CPU load) and a service that is used by the client to reach the database.
Each iteration of this workload can be broken down in:
  - 1 deployment holding a postgresql database
  - 1 deployment holding a client application for the previous database
  - 1 service pointing to the postgresl database


### Configuration file

An [env.sh](env.sh) file is provided with all available configuration parameters.

