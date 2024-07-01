# Deprecation notice

### The workloads and scripts in this directory are not actively maintained or supported and shouldn't be used anymore, use [kube-burner-ocp-wrapper](../kube-burner-ocp-wrapper) instead.

---

# Kube-burner e2e benchmarks

In order to kick off one of these benchmarks you must use the run.sh script. There are 13 different workloads at the moment, that could be launched as follows:

- **`cluster-density`**: `WORKLOAD=cluster-density ./run.sh`
- **`node-density`**: `WORKLOAD=node-density ./run.sh`
- **`node-density-heavy`**: `WORKLOAD=node-density-heavy ./run.sh`
- **`node-density-cni`**: `WORKLOAD=node-density-cni ./run.sh`
- **`node-density-cni-networkpolicy`**: `WORKLOAD=node-density-cni-networkpolicy ./run.sh`
- **`pods-service-route`**: `WORKLOAD=pods-service-route ./run.sh`
- **`max-namespaces`**: `WORKLOAD=max-namespaces ./run.sh`
- **`max-services`**: `WORKLOAD=max-services./run.sh`
- **`pod-density`**: `WORKLOAD=pod-density ./run.sh`
- **`pod-density-heavy`**: `WORKLOAD=pod-density-heavy ./run.sh`
- **`custom`**: `WORKLOAD=custom ./run.sh`
- **`concurrent-builds`**: `WORKLOAD=concurrent-builds ./run.sh`
- **`cluster-density-ms`**: `WORKLOAD=cluster-density-ms ./run.sh`
- **`networkpolicy-case1`**: `WORKLOAD=networkpolicy-case1 ./run.sh`
- **`networkpolicy-case2`**: `WORKLOAD=networkpolicy-case2 ./run.sh`
- **`networkpolicy-case3`**: `WORKLOAD=networkpolicy-case3 ./run.sh`
- **`large-networkpolicy-egress`**: `WORKLOAD=large-networkpolicy-egress ./run.sh`

## Environment variables

Workloads can be tweaked with the following environment variables:


| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **INDEXING**         | Enable/disable indexing         | true    |
| **ES_SERVER**        | Elasticsearch endpoint          | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | Elasticsearch index             | ripsaw-kube-burner|
| **PROM_URL**         | Prometheus endpoint, it should be Thanos querier endpoint when running on `HYPERSHIFT` cluster | Prometheus endpoint is automatically discovered |
| **JOB_TIMEOUT**      | Kube-burner's timeout, in seconds | 4h (4 hours) |
| **QPS**              | Queries/sec                     | 20      |
| **BURST**            | Maximum number of simultaneous queries | 20      |
| **POD_NODE_SELECTOR**| nodeSelector for pods created by the kube-burner workloads | {node-role.kubernetes.io/worker: } |
| **WORKER_NODE_LABEL**| Label to select nodes used for the kube-burner workloads | node-role.kubernetes.io/worker |
| **POD_WAIT**         | Wait for pods to be ready in each iteration | false |
| **MAX_WAIT_TIMEOUT** | Kube-burner will time out when the pods deployed take more that this value to be ready | 1h |
| **WAIT_FOR**         | Wait for the resources of this list to be ready | [] (empty means all of them) |
| **VERIFY_OBJECTS**   | Verify objects created by kube-burner | true |
| **ERROR_ON_VERIFY**  | Make kube-burner pod to hang when verification fails | true |
| **STEP_SIZE**        | Prometheus step size, useful for long benchmarks | 30s|
| **PRELOAD_IMAGES**   | Preload kube-buner's benchmark images in the cluster | true |
| **PRELOAD_PERIOD**   | How long the preload stage will last | 2m |
| **CLEANUP**          | Delete old namespaces for the selected workload before starting benchmark | true |
| **CLEANUP_WHEN_FINISH** | Delete benchmark objects and workload's namespaces after running it | false |
| **CLEANUP_TIMEOUT**  | Timeout value used in resource deletion | 30m |
| **KUBE_BURNER_URL** | Kube-burner tarball URL | https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.17.3/kube-burner-0.17.3-Linux-x86_64.tar.gz |
| **BUILD_FROM_REPO** | Rather than downloading the previous tarball, build the kube-burner binary using a specific git repository.  Ex. https://github.com/rsevilla87/kube-burner | "" (Disabled) |
| **LOG_LEVEL**        | Kube-burner log level | info |
| **PPROF_COLLECTION** | Collect and store pprof data locally | false |
| **PPROF_COLLECTION_INTERVAL** | Intervals for which pprof data will be collected | 5m | 
| **HYPERSHIFT** | Boolean, to be set if its a hypershift hosted cluster | false |
| **MGMT_CLUSTER_NAME**        | Management cluster name of the hosted cluster, used for metric collections when `INDEXING` is enabled | |
| **HOSTED_CLUSTER_NS** | HostedControlPlane namespace of the cluster, used for metric collections when `INDEXING` is enabled | |
| **THANOS_RECEIVER_URL** | Thanos receiver url endpoint for grafana remote-write agent |  | 
| **POD_READY_THRESHOLD** | Pod ready latency threshold (only applies node-density and pod-density workloads). [More info](https://kube-burner.readthedocs.io/en/latest/measurements/#pod-latency-thresholds) | 5000ms |
| **PLATFORM_ALERTS** | Platform alerting enables, kube-burner alerting based cluster's platform, either ALERT_PROFILE or this variable can be set | false |
| **COMPARISON_CONFIG**        | Touchstone configs. Multiple config files can be passed here. Ex. COMPARISON_CONFIG="podCPU-avg.json clusterVersion.json". [Sample files](../../utils/touchstone-configs) |  |
| **TOUCHSTONE_NAMESPACE**        | Namespace where we query for metrics specified in touchstone config files | openshift-sdn or openshift-ovn-kubernetes |
| **GSHEET_KEY_LOCATION**        | Location of service account key to generate google sheets |  |
| **EMAIL_ID_FOR_RESULTS_SHEET**        | Email id where the google sheets needs to be sent |  |
| **GEN_CSV**             | Generate a benchmark-comparison csv, required to generate the spreadsheet | "false" |
| **KUBE_DIR**             | The directory where to place the kube-burner executable | /tmp |
| **CHURN**             | Enable "churning" of the workload after the objects are created | "false" |
| **CHURN_DURATION**             | Time, in time type (ex: 1h10m11s), to churn for | 10m |
| **CHURN_DELAY**             | Time, in time type (ex: 1m30s), to wait between each churn | 60s |
| **CHURN_PERCENT**             | Percentage of JOB_ITERATIONS that we should churn each round | 10 |
| **NAMESPACED_ITERATIONS**             | Run each JOB_ITERATIONS in a distinct namespace.  Configurable on node-density-heavy and node-density-cni only | false |

**Note**: You can use basic authentication for ES indexing using the notation `http(s)://[username]:[password]@[host]:[port]` in **ES_SERVER**.

### Cluster-density variables

The `cluster-density` workload supports the environment variable **JOB_ITERATIONS**. This variable configures the number of cluster-density jobs iterations to perform (1 namespace per iteration). By default 1000.

Each iteration creates the following objects:

- 1 imagestream
- 1 build
- 5 deployments with pod 2 replicas (sleep) mounting 4 secrets, 4 configmaps and 1 downwardAPI volume each
- 5 services, each one pointing to the TCP/8080 and TCP/8443 ports of one of the previous deployments
- 1 route pointing to the to first service
- 10 secrets containing 2048 character random string
- 10 configMaps containing a 2048 character random string

### Node-density and Node-density-heavy variables

The `node-density` and `node-density-heavy` workloads support the following environment variables:

- **NODE_COUNT**: Number of worker nodes to deploy the pods on. During the workload nodes will be labeled with `node-density=enabled`. Defaults to the number of worker nodes across the cluster (Nodes resulting of the expression `oc get node -o name --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",${WORKER_NODE_LABEL}`
- **PODS_PER_NODE**: Define the maximum number of pods to deploy on each labeled node. Defaults to 245
- **NODE_POD_DENSITY_IMAGE**: Image to use as node-pod-density workload. Defaults to `gcr.io/google_containers/pause:3.1`.

These workloads create different objects each:

- **node-density**: Creates a single namespace with a number of Deployments proportional to the calculated number of pod.
Each iteration of this workload creates the following object:
  - 1 pod. (sleep)

- **node-density-heavy**. Creates a **single namespace with a number of applications proportional to the calculated number of pods / 2**. This application consists on two deployments (a postgresql database and a simple client that generates some CPU load) and a service that is used by the client to reach the database.
Single namespace behavior can be changed by using `NAMESPACED_ITERATIONS`.
Each iteration of this workload can be broken down in:
  - 1 deployment holding a postgresql database
  - 1 deployment holding a client application for the previous database
  - 1 service pointing to the postgresl database

- **node-density-cni**. Creates a **single namespace with a number of applications equals to job_iterations**. This application consists on two deployments (a node.js webserver and a simple client that curls the webserver) and a service that is used by the client to reach the webserver.
Single namespace behavior can be changed by using `NAMESPACED_ITERATIONS`.
Each iteration of this workload creates the following objects:
  - 1 deployment holding a node.js webserver
  - 1 deployment holding a client application for curling the webserver
  - 1 service pointing to the webserver

    The startupProbe of the client pod depends on being able to reach the webserver so that the PodReady latencies collected by kube-burner reflect network connectivity.

- **node-density-cni-networkpolicy**. Creates a **single namespace with a number of applications equals to job_iterations**. This application consists on two deployments (a node.js webserver and a simple client that curls the webserver) and a service that is used by the client to reach the webserver.
Each iteration of this workload creates the following objects:
  - 1 deployment holding a node.js webserver
  - 1 deployment holding a client application for curling the webserver
  - 1 service pointing to the webserver

    A NetworkPolicy to deny all connections is created in the namspace first and then NetworkPolicies specifically applying the connection of each client-webserver pair are applied. The startupProbe of the client pod depends on being able to reach the webserver so that the PodReady latencies collected by kube-burner reflect network connectivity.

- **pods-service-route**. Creates `NAMESPACE_COUNT` namespaces, each with 10 webserver pods fronted by 10 services each exposed as a route. The routes and services are accessed by application pods that curl the webserver.
Each iteration of this workload creates the following objects:
  - 1 namespace
  - 10 deployments, each consisting a node.js webserver pod
  - 10 deployments, each consisting of a client application pod for curling the webserver
  - 10 services each pointing to a unique webserver
  - 10 routes, 1 for each service

    The startupProbe of the client pod depends on being able to reach a random webserver service in the namespace and a a random route from all the namesapces, so that the PodReady latencies collected by kube-burner reflect network connectivity.

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

### Concurrent Builds

Creates a buildconfig and imagestream for a specified application(s) (defined in **APP_LIST** env variable). **This
 will create as many namespaces with these objects as the configured job_iterations**.
After the initial creation of the objects the script will concurrently build different numbers (defined by
 **BUILD_LIST**) of the builds and output the average times. 
To edit any of the build information edit the bash script correlating with the application of interest under the
 [builds](./builds) folder

**NOTE**: Do not edit parameters other than BUILD_LIST and APP_LIST in env variables file. They will be overwritten
 be the data in builds folder. If you need to make updates to application data, edit environment variables under
  builds/<application_name>.sh

### Cluster-density-ms variables

The `cluster-density-ms` workload is for managed service clusters and currently being used only on hypershift hosted cluster. It supports the environment variable **JOB_ITERATIONS**, this variable configures the number of jobs iterations to perform (1 namespace per iteration). By default 75. To index results, set **PROM_URL**(to thanos querier endpoint), **HYPERSHIFT**, **MGMT_CLUSTER_NAME**, **HOSTED_CLUSTER_NS**

Each iteration creates the following objects: 

- 1 imagestream
- 2 deployments with pod 2 replicas (sleep) mounting 4 secrets, 4 configmaps and 1 downwardAPI volume each
- 2 services, each one pointing to the TCP/8080 and TCP/8443 ports of one of the previous deployments
- 1 route pointing to the to first service
- 20 secrets containing 2048 character random string
- 10 configMaps containing a 2048 character random string

### Churn

Churning a workload allows you to scale down and then up a percentage of **JOB_ITERATIONS** after the objects have been created. It takes in a percentage, **CHURN_PERCENT**, which is the percentage of JOB_ITERATIONS it churns during each cycle. It will delete and recreate **ALL** the objects specified in the job definition. After each churn cycle it will sleep for the **CHURN_DELAY**. This loop continues until the **CHURN_DURATION** has elapsed.

To churn 20% of your **JOB_ITERATIONS** every 30 seconds for a total duration (the calculated time from when the first churn begins + the **CHURN_DURATION**) of 60 minutes you would utilize these variables:

- **CHURN**=true
- **CHURN_DURATION**=60m
- **CHURN_PERCENT**=20
- **CHURN_DELAY**=30s

**NOTE: The churn functionality is only implemented for namespacedIteration creation jobs (ex: cluster-density)**

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

### Alerts

Syntax reference in kube-burner documentation: https://kube-burner.readthedocs.io/en/latest/alerting/. The special variable `{{ .elapsed }}` takes the value of the workload duration. The metric up returns 0 when the service in question is down.

Some of the alerts defined use the [avg_over_time function](https://prometheus.io/docs/prometheus/latest/querying/functions/#aggregation_over_time) to prevent firing when the metric suffers isolated spikes.

Three metric profiles are defined in the [alerts-profiles directory](alerts-profiles):
- ci.yml: This is meant for CI purposes, all the expressions here have warning severity
- cluster-density.yml: By default, used by the cluster-density workload.
