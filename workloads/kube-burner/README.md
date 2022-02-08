# Kube-burner e2e benchmarks

In order to kick off one of these benchmarks you must use the run.sh script. There are 8 different workloads at the moment, that could be launched as follows:

- **`cluster-density`**: `WORKLOAD=cluster-density ./run.sh`
- **`node-density`**: `WORKLOAD=node-density ./run.sh`
- **`node-density-heavy`**: `WORKLOAD=node-density-heavy ./run.sh`
- **`node-density-cni`**: `WORKLOAD=node-density-cni ./run.sh`
- **`node-density-cni-networkpolicy`**: `WORKLOAD=node-density-cni-networkpolicy ./run.sh`
- **`max-namespaces`**: `WORKLOAD=max-namespaces ./run.sh`
- **`max-services`**: `WORKLOAD=max-services./run.sh`
- **`pod-density`**: `WORKLOAD=pod-density ./run.sh`
- **`pod-density-heavy`**: `WORKLOAD=pod-density-heavy ./run.sh`
- **`custom`**: `WORKLOAD=custom ./run.sh`

## Environment variables

Workloads can be tweaked with the following environment variables:


| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **OPERATOR_REPO**    | Benchmark-operator repo         | https://github.com/cloud-bulldozer/benchmark-operator.git      |
| **OPERATOR_BRANCH**  | Benchmark-operator branch       | master  |
| **INDEXING**         | Enable/disable indexing         | true    |
| **ES_SERVER**        | Elasticsearch endpoint          | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | Elasticsearch index             | ripsaw-kube-burner|
| **PROM_URL**         | Prometheus endpoint             | https://prometheus-k8s.openshift-monitoring.svc.cluster.local:9091|
| **METADATA_COLLECTION**   | Enable metadata collection | true (If indexing is disabled metadata collection will be also disabled) |
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
| **CLEANUP**          | Delete old namespaces for the selected workload before starting benchmark | false |
| **CLEANUP_WHEN_FINISH** | Delete workload's namespaces after running it | false |
| **KUBE_BURNER_IMAGE** | Kube-burner container image | quay.io/cloud-bulldozer/kube-burner:v0.14.3 |
| **LOG_LEVEL**        | Kube-burner log level | info |
| **PPROF_COLLECTION** | Collect and store pprof data locally | false |
| **PPROF_COLLECTION_INTERVAL** | Intervals for which pprof data will be collected | 5m | 
| **TEST_CLEANUP**     | Remove benchmark CR at the end | true |
| **POD_READY_THRESHOLD** | Pod ready latency threshold (only applies node-density and pod-density workloads). [More info](https://kube-burner.readthedocs.io/en/latest/measurements/#pod-latency-thresholds) | 5000ms |

**Note**: You can use basic authentication for ES indexing using the notation `http(s)://[username]:[password]@[host]:[port]` in **ES_SERVER**.

### Cluster-density variables

The `cluster-density` workload supports the environment variable **JOB_ITERATIONS**. This variable configures the number of cluster-density jobs iterations to perform (1 namespace per iteration). By default 1000.

Each iteration creates the following objects:

- 12 imagestreams
- 3 buildconfigs
- 6 builds
- 1 deployment with 2 pod replicas (sleep) mounting two secrets each. deployment-2pod
- 2 deployments with 1 pod replicas (sleep) mounting two secrets. deployment-1pod
- 3 services, one pointing to deployment-2pod, and other two pointing to deployment-1pod. (As a consequence, 3 endpoint objects pointing to 4 pods are created)
- 3 route. 1 pointing to the service deployment-2pod and other two pointing to deployment-1pod
- 10 secrets. 2 of them mounted by the previous deployments.
- 10 configMaps. 2 of them mounted by the previous deployments.

### Node-density and Node-density-heavy variables

The `node-density` and `node-density-heavy` workloads support the following environment variables:

- **NODE_COUNT**: Number of worker nodes to deploy the pods on. During the workload nodes will be labeled with `node-density=enabled`. Defaults to the number of worker nodes across the cluster (Nodes resulting of the expression `oc get node -o name --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker=`
- **PODS_PER_NODE**: Define the maximum number of pods to deploy on each labeled node. Defaults to 245

These workloads create different objects each:

- **node-density**: Creates a single namespace with a number of Deployments proportional to the calculated number of pod.
Each iteration of this workload creates the following object:
  - 1 pod. (sleep)

- **node-density-heavy**. Creates a **single namespace with a number of applications proportional to the calculated number of pods / 2**. This application consists on two deployments (a postgresql database and a simple client that generates some CPU load) and a service that is used by the client to reach the database.
Each iteration of this workload can be broken down in:
  - 1 deployment holding a postgresql database
  - 1 deployment holding a client application for the previous database
  - 1 service pointing to the postgresl database

- **node-density-cni**. Creates a **single namespace with a number of applications equals to job_iterations**. This application consists on two deployments (a node.js webserver and a simple client that curls the webserver) and a service that is used by the client to reach the webserver.
Each iteration of this workload creates the following objects:
  - 1 deployment holding a node.js webserver
  - 1 deployment holding a client application for curling the webserver
  - 1 service pointing to the webserver

    The startupProbe of the client pod depends on being able to reach the webserver so that the PodReady latencies collected by kube-burner reflect network connectivity.

- **node-density-cni-policy**. Creates a **single namespace with a number of applications equals to job_iterations**. This application consists on two deployments (a node.js webserver and a simple client that curls the webserver) and a service that is used by the client to reach the webserver.
Each iteration of this workload creates the following objects:
  - 1 deployment holding a node.js webserver
  - 1 deployment holding a client application for curling the webserver
  - 1 service pointing to the webserver

    A NetworkPolicy to deny all connections is created in the namspace first and then NetworkPolicies specifically applying the connection of each client-webserver pair are applied. The startupProbe of the client pod depends on being able to reach the webserver so that the PodReady latencies collected by kube-burner reflect network connectivity.

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

For example, the command:

```shell
$ INDEXING=false WORKLOAD_TEMPLATE=my-config/kube-burner.cfg METRICS_PROFILE=my-metrics/metrics.yml ALERTS_PROFILE=my-alerts/alerts-profile.yml WORKLOAD=custom ./run.sh
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
