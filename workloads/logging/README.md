# Logging

The purpose of this script is to deploy the logging stack which includes Elasticsearch, Fluentd and Kibana on an OpenShift cluster.


## Cluster Logging Stack Installation
```
$ ./deploy_logging_stack.sh
```
This deploys the cluster-logging-operator which creates and manages the Elasticsearch cluster, Fluentd DaemonSet - pod on each of the nodes and Kibana in openshift-logging namespace.

## Test Run
```
$ ./run_logging_test.sh
```
This runs the logging test based on env.sh parameters. If **DEPLOY_LOGGING** is set to `True`, it will also install Cluster Logging Stack using `deploy_logging_stack.sh` script


## Environment variables
Ensure to have `KUBECONFIG` set to the proper path to your desired cluster.

### CHANNEL
Default: `stable-5.5`
Update channel for the Elasticsearch and Cluster logging operators.

### CUSTOM_ES_URL
Default: ""
The external Elasticsearch url to direct logs to
NOTE: If set, internal ElasticSearch will not be configured

### ES_NODE_COUNT
Default: 3
Number of Elasticsearch nodes.

### ES_STORAGE_CLASS
Default: 'gp3-csi'
Storage class to use for the persistent storage. The faster the storage, better the Elasticsearch performance.

### ES_STORAGE_SIZE
Default: `100G`
Each data node in the cluster is bound to a Persistent Volume Claim that requests the size specified using this variable from the cloud storage.

### ES_MEMORY_LIMITS
Default: `16Gi`
Memory limits for the Elasticsearch as needed.

### ES_MEMORY_REQUESTS
Default: `16Gi`
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

### FORWARD_LOGS
Default: [application]
Logs to forward to the Elasticsearch backend. Only application logs are forwarded by default, the parameter can be tweaked to forward infra and audit logs. Supported options: [infra, application, audit].

### TIMEOUT
Default: 180
Time to wait for resources created before exiting

### DEBUG
Default: true
Enable debug logging on snafu execution

### TEST_CLEANUP
Default: true
Remove benchmark CR at the end

### TEST_TIMEOUT
Default: 7200
Benchmark timeout in seconds

**NOTE**: [Instance](files/logging-stack.yml) can be modified in case you want to add/tweak the configuration.


## Suggested configuration
[Log store guide](https://docs.openshift.com/container-platform/4.12/logging/cluster-logging-deploying.html#cluster-logging-deploy-cli_cluster-logging-deploying) can be used to configure the stack depending on the scale, performance and redundancy we need. The following variables can be exported as the environment variables to tweak the supported parameters:

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
export FORWARD_LOGS=[infra, application, audit]
export TIMEOUT=180
```
