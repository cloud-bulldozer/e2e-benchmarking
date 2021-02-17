# scale-ci-diagnosis

Tool to help diagonose issues with OpenShift clusters. It does it by:
- capturing prometheus DB from the running prometheus pods to local file system. This can be used to look at the metrics later by running prometheus locally with the backed up DB.
- Capturing openshift cluster information including  all the operator managed components using https://github.com/openshift/must-gather.

It also supports running conformance or end-to-end tests to make sure cluster is sane.

## Run
```
Edit env.sh according to the needs and run the ocp_diagnosis script:

$ source env.sh; ./ocp_diagnosis.sh

options supported:
	OUTPUT_DIR=str,                       str=dir to store the capture prometheus data
	PROMETHEUS_CAPTURE=str,               str=true or false, enables/disables prometheus capture
	PROMETHEUS_CAPTURE_TYPE=str,          str=wal or full, wal captures the write ahead log and full captures the entire prometheus DB
	OPENSHIFT_MUST_GATHER=str,            str=true or false, gathers cluster data including information about all the operator managed components
	STORAGE_MODE=str,                     str=pbench, moves the results to the pbench results dir to be shipped to the pbench server in case the tool is run using pbench
	DATA_SERVER_URL=str                   str=url that points to http server that hosts data
```

### Pbench server for storage
[Pbench](https://github.com/distributed-system-analysis/pbench.git) does a great job in terms of both collection and long term storage. The tool currently supports pbench as the storage mode instead of just storing the results on the local file system, we will be adding support to store results in Amazon S3 in the future.

In order to use pbench as the storage, the tool needs to be run using pbench and STORAGE_MODE should be set to pbench:

```
$ source env.sh; pbench-user-benchmark --sysinfo=none -- <path to ocp_diagnosis.sh>
# pbench-move-results --prefix ocp-diagnosis-$(date +"%Y%m%d-%H%M%S")
```

### Snappy data server for storage

[Snappy data server](https://github.com/openshift-scale/snappy-data-server) is a second option for storage on a filesystem. The easiest option is to deploy the data server on your host. Refer to [setup](https://github.com/openshift-scale/snappy-data-server#Setup) and [usage](https://github.com/openshift-scale/snappy-data-server#Usage) to deploy the data server. Once deployed, you can read over it's API at it's `/docs` route.

[Snappy CLI](https://github.com/mfleader/snappyCLI) is a client you can use in your shell scripting.

Declare environment variables:

```shell
DATA_SERVER_USERNAME=your_username@email.com
DATA_SERVER_PASSWORD=your_password
```

### Visualize the captured data locally on prometheus server
Launch a prometheus server and load the captured/unpacked DB:
```
$ podman run --privileged --name=prometheus-server --net=host -v <path-to-unpacked-prom-db>:/prometheus -p 9090:9090 docker.io/prom/prometheus
```
This installs prometheus server and loads up the DB, the server can be accessed at https://0.0.0.0:9090.

Run grafana container with pre-loaded dashboards from https://github.com/cloud-bulldozer/performance-dashboards with prometheus as the default datasource, it can be accessed at http://0.0.0.0:3000:
```
$ podman run --name=scale-ci-diagnosis --net=host -d -p 3000:3000 quay.io/openshift-scale/visualize-metrics:latest 
```

### Conformance

Conformance runs the end-to-end test suite to check the sanity of the OpenShift cluster.

Assuming that the podman is installed, conformance/e2e test can be run using the following command:
```
$ podman run --privileged=true --name=conformance -d -v <path-to-kubeconfig>:/root/.kube/config quay.io/openshift-scale/conformance:latest
$ podman logs -f conformance
```

Similarly, docker can be used to run the conformance test:
```
$ docker run --privileged=true --name=conformance -d -v <path-to-kubeconfig>:/root/.kube/config quay.io/openshift-scale/conformance:latest
$ docker logs -f conformance
```
