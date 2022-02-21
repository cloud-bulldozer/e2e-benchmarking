# Kube-burner e2e benchmarks

The purpose of these scripts is to run a kube-burner workload steered by ripsaw. There are 3 types of workloads at the moment:

- **`cluster-density`**: Triggered by `run_clusterdensity_test_fromgit.sh`
- **`node-density`**: Triggered by `run_nodedensity_test_fromgit.sh`
- **`node-density-heavy`**: Triggered by `run_nodedensity-heavy_test_fromgit.sh`
- **`max-namespaces`**: Triggered by `run_maxnamespaces_test_fromgit.sh`
- **`max-services`** Triggered by `run_maxservices_test_fromgit.sh`
- **`pod-density`**: Triggered by `run_poddensity_test_fromgit.sh`
- **`pod-density-heavy`**: Triggered by `run_poddensity-heavy_test_fromgit.sh`

## Environment variables

All scripts can be tweaked with the following environment variables:

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **OPERATOR_REPO**              | Benchmark-operator repo                     | https://github.com/cloud-bulldozer/benchmark-operator.git      |
| **OPERATOR_BRANCH**              | Benchmark-operator branch                     | master      |
| **INDEXING**         | Enable/disable indexing         | true    |
| **ES_SERVER**        | Elastic search endpoint         | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | Elastic search index            | ripsaw-kube-burner|
| **PROM_URL**         | Prometheus endpoint         | https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091|
| **METADATA_COLLECTION**    | Enable metadata collection | true (If indexing is disabled metadata collection will be also disabled) |
| **JOB_TIMEOUT**      | Kube-burner's job timeout, in seconds      | 14400 (4 hours) |
| **POD_READY_TIMEOUT**| Timeout for kube-burner and benchmark-operator pods to be running | 180 |
| **NODE_SELECTOR**    | The kube-burner pod deployed by benchmark-operator will use this node selector          | {node-role.kubernetes.io/worker: } |
| **QPS**              | Queries/sec                     | 20      |
| **BURST**            | Maximum number of simultaneous queries | 20      |
| **POD_NODE_SELECTOR**| nodeSelector for pods created by the kube-burner workloads | {node-role.kubernetes.io/worker: } |
| **POD_WAIT**         | Wait for pods to be ready in each iteration | false |
| **MAX_WAIT_TIMEOUT** | Kube-burner will time out when the pods deployed take more that this value to be ready | 1h |
| **WAIT_FOR**         | Wait for the resources of this list to be ready | [] (empty means all of them) |
| **VERIFY_OBJECTS**   | Verify objects created by kube-burner | true |
| **ERROR_ON_VERIFY**  | Make kube-burner pod to hang when verification fails | true |
| **STEP_SIZE**        | Prometheus step size, useful for long benchmarks | 30s|
| **PRELOAD_IMAGES**   | Preload kube-buner's benchmark images in the cluster | true |
| **PRELOAD_PERIOD**   | How long the preload stage will last | 2m |
| **LOG_STREAMING**    | Enable log streaming of kube-burner pod | true |
| **CLEANUP**          | Delete workload's old namespaces and kube-burner config configmap before starting the benchmark | false |
| **CLEANUP_WHEN_FINISH** | Delete workload's namespaces after running it | false |
| **KUBE_BURNER_IMAGE** | Kube-burner container image | quay.io/cloud-bulldozer/kube-burner:v0.14.3 |
| **LOG_LEVEL**        | Kube-burner log level | info |
| **PPROF_COLLECTION** | Collect and store pprof data locally | false |
| **PPROF_COLLECTION_INTERVAL** | Intervals for which pprof data will be collected | 5m | 
| **TEST_CLEANUP**     | Remove benchmark CR at the end | true |

**Note**: You can use basic authentication for ES indexing using the notation `http(s)://[username]:[password]@[host]:[port]` in **ES_SERVER**.

### Cluster-density variables

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

### Node-density and Node-density-heavy variables

The `node-density` and `node-density-heavy` workloads support the following environment variables:

- **NODE_COUNT**: Number of worker nodes to deploy the pods on. During the workload nodes will be labeled with `node-density=true`. Defaults to 4.
- **PODS_PER_NODE**: Define the maximum number of pods to deploy on each labeled node. Defaults to 250

These workloads create different objects each:

- **node-density**: Creates a single namespace with a number of Deployments proportional to the calculated number of pod.
Each iteration of this workload creates the following object:
  - 1 pod. (sleep)

- **node-density-heavy**. Creates a **single namespace with a number of applications proportional to the calculated number of pods / 2**. This application consists on two deployments (a postgresql database and a simple client that generates some CPU load) and a service that is used by the client to reach the database.
Each iteration of this workload can be broken down in:
  - 1 deployment holding a postgresql database
  - 1 deployment holding a client application for the previous database
  - 1 service pointing to the postgresl database

### Max-namespaces

The number of namespaces created by Kube-burner is defined by the variable `NAMESPACE_COUNT`. Each namespace is created with the following objects:

- 1 deployment holding a postgresql database
- 5 deployments consisting of a client application for the previous database
- 1 service pointing to the postgresl database
- 10 secrets

### Max-services

It creates n-replicas of an application deployment (hello-openshift) and a service in a single namespace as defined by the environment variable `SERVICE_COUNT`.

### Pod-density

It creates as many "sleep" pods as configured in the environment variable `PODS`.

### Pod-density-heavy

A heavier variant of the pod density workload, where rather than creating sleep pods , a hello-openshift application is deployed (quay.io/cloud-bulldozer/hello-openshift:latest). The application continuously services an HTTP response of "Hello OpenShift!" on port 8080 on the "/" path. Various Probes are used on the application. startupprobe checks if the http response is set at the specified port and path. If successfuly started the readiness and liveness probes run. readinessprobe executes an "ls" shell command to check if the container is ready. livenessprobe executes an "echo" command to check if container is running and if not restarts it. liveness and readiness probes run regularly at 5s intervals to check the status of the application.  

### Launching custom workloads

Apart from the pre-defined workloads and metric profiles available in this repo, you can use your own benchmark, metric-profile and alert-profile. The following environment variables can be used to configure the source for the different configuration files:

- **`WORKLOAD_TEMPLATE`**: Path to the kube-burner's workload configuration file, the templates must be defined in the same directory where this file is
- **`METRICS_PROFILE`**: Path to the kube-burner metrics-profile. (Optional)
- **`ALERTS_PROFILE`**: Path to the kube-burner alert-profile. (Optional)

The script `run_custom_workload_fromgit.sh` provides a shortcut to launch the benchmark.

For example, the command:

```shell
$ INDEXING=false WORKLOAD_TEMPLATE=my-config/kube-burner.cfg METRICS_PROFILE=my-metrics/metrics.yml ALERTS_PROFILE=my-alerts/alerts-profile.yml ./run_custom_workload_fromgit.sh
```

will launch a pod running a kube-burner process that will use the configuration file defined at https://raw.githubusercontent.com/cloud-bulldozer/cluster-perf-ci/master/configmap-scale.yml


### Snappy integration configurations

To backup data to a given snappy data-server

#### Environment Variables

**`ENABLE_SNAPPY_BACKUP`**
Default: ''
Set to true to backup the logs/files generated during a workload run

**`SNAPPY_DATA_SERVER_URL`**
Default: ''
The Snappy data server url, where you want to move files.

**`SNAPPY_DATA_SERVER_USERNAME`**
Default: ''
Username for the Snappy data-server.

**`SNAPPY_DATA_SERVER_PASSWORD`**
Default: ''
Password for the Snappy data-server.

**`SNAPPY_USER_FOLDER`**
Default: 'perf-ci'
To store the data for a specific user.

