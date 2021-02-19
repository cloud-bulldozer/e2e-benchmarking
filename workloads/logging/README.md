# Logging

The purpose of this script is to deploy the logging stack which includes Elasticsearch, Fluentd and Kibana on an OpenShift cluster.


## Run
```
$ ./deploy_logging_stack.sh
```
This deploys the cluster-logging-operator which creates and manages the Elasticsearch cluster, Fluentd DaemonSet - pod on each of the nodes and Kibana in openshift-logging namespace.


## Environment variables

### KUBECONFIG_PATH
Default: `$HOME/.kube/config`
Path to the kubeconfig to get access to the OpenShift cluster.

### CHANNEL
Default: `4.6`
Update channel for the Elasticsearch and Cluster logging operators.

### ES_NODE_COUNT
Default: 3     
Number of Elasticsearch nodes.

### ES_STORAGE_CLASS
Default: 'gp2'
Storage class to use for the persistent storage. The faster the storage, better the Elasticsearch performance.

### ES_STORAGE_SIZE
Default: `100G`
Each data node in the cluster is bound to a Persistent Volume Claim that requests the size specified using this variable from the cloud storage.

### ES_MEMORY_REQUESTS
Default: `8Gi`
Memory requests for the Elasticsearch as needed.

### ES_PROXY_MEMORY_LIMITS
Default: `256Mi`
Limit requests for the Elasticsearch proxy as needed.

### ES_PROXY_MEMORY_REQUESTS
Default: `256Mi`
Memory requests for the Eleasticsearch proxy as needed.

### ES_REDUNDANCY_POLICY
Default: `SingleRedundancy`
Redundancy policy for the shards. Supported options: FullRedundancy, MultipleRedundancy, SingleRedundancy and ZeroRedundancy.
Elasticsearch makes one copy of the primary shards for each index in case of SingleRedundancy. Logs are always available and recoverable as long as at least two data nodes exist. Refer [docs](https://docs.openshift.com/container-platform/4.6/logging/config/cluster-logging-log-store.html#cluster-logging-elasticsearch-ha_cluster-logging-store) for more information.

### FLUENTD_MEMORY_LIMITS
Default: `1Gi`
Memory limits for the Fluentd as needed.

### FLUENTD_CPU_REQUESTS
Default: `500m`
CPU requests for the Fluentd as needed.

### FLUENTD_MEMORY_REQUESTS
Default: `1Gi`
Memory requests for the Fluentd as needed.

### TIMEOUT
Default: 180
Time to wait for resources created to be up before exiting

**NOTE**: [Instance](files/logging-stack.yml) can be modified in case you want to add/tweak the configuration.


## Suggested configuration
[Log store guide](https://docs.openshift.com/container-platform/4.6/logging/config/) can be used to configure the stack depending on the scale, performance and redundancy we need. The following variables can be exported as the environment variables to tweak the supported parameters:

```sh
export CHANNEL=
export ES_NODE_COUNT=3
export ES_STORAGE_CLASS=
export ES_STORAGE_SIZE=
export ES_MEMORY_REQUESTS=
export ES_PROXY_MEMORY_LIMITS=
export ES_PROXY_MEMORY_REQUESTS=
export ES_REDUNDANCY_POLICY=SingleRedundancy
export FLUENTD_MEMORY_LIMITS=
export FLUENTD_CPU_REQUESTS=
export FLUENTD_MEMORY_REQUESTS=
export TIMEOUT=180
```
