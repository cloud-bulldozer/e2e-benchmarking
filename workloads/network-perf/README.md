# Network Scripts

The purpose of the network scripts is to run uperf workload on the Openshift Cluster.
There are 4 types network tests:
1. pod to pod using Hostnetwork
2. pod to pod using SDN
3. pod to pod using Service
4. pod to pod using Multus (NetworkAttachmentDefinition needs to be provided)

Running from CLI:

```sh
$ ./run_<test-name>_network_test_fromgit.sh 
```

## Environment variables

### ES_SERVER
Default: `milton.aws.com`  
Public elasticsearch server

### ES_PORT
Default: `80`  
Port number for public elasticsearch server

### METADATA_COLLECTION
Default: `true`   
Enable/Disable collection of metadata

### COMPARE
Default: `false`   
Enable/Disable the ability to compare two uperf runs. If set to `true`, the next set of environment variables pertaining to the type of test are required

### ES_SERVER_BASELINE 
Default: `search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com`   
Elasticsearch server used used by the baseline run 

### ES_PORT_BASELINE
Default: `80`  
Port number for the elasticsearch server used by the baseline run

### BASELINE_HOSTNET_UUID
Default: ``   
Baseline UUID for hostnetwork test  

### BASELINE_POD_1P_UUID
Default: ``   
Baseline UUID for pod to pod using SDN test with 1 uperf client-server pair

### BASELINE_POD_2P_UUID
Default: ``   
Baseline UUID for pod to pod using SDN test with 2 uperf client-server pair

### BASELINE_POD_4P_UUID
Default: ``   
Baseline UUID for pod to pod using SDN test with 4 uperf client-server pair

### BASELINE_SVC_1P_UUID
Default: ``   
Baseline UUID for pod to pod using service test with 1 uperf client-server pair

### BASELINE_SVC_2P_UUID
Default: ``   
Baseline UUID for pod to pod using service test with 2 uperf client-server pair

### BASELINE_SVC_4P_UUID
Default: ``   
Baseline UUID for pod to pod using service test with 4 uperf client-server pair

### BASELINE_MULTUS_UUID
Default: ``   
Baseline UUID for multus test

### THROUGHPUT_TOLERANCE
Default: `5`   
Accepeted deviation in percentage for throughput when compared to a baseline run

### LATENCY_TOLERANCE
Default: `5`   
Accepeted deviation in percentage for latency when compared to a baseline run


## Suggested configurations

```sh
export ES_SERVER=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
export ES_PORT=80
export METADATA_COLLECTION=true
export COMPARE=true
export ES_SERVER_BASELINE=search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com
export ES_PORT_BASELINE=80
export BASELINE_HOSTNET_UUID=
export BASELINE_POD_1P_UUID=
export BASELINE_POD_2P_UUID=
export BASELINE_POD_4P_UUID=
export BASELINE_SVC_1P_UUID=
export BASELINE_SVC_2P_UUID=
export BASELINE_SVC_4P_UUID=
export BASELINE_MULTUS_UUID=
export THROUGHPUT_TOLERANCE=5
export LATENCY_TOLERANCE=5
```

