# Network Scripts

The purpose of the network scripts is to run uperf workload on the Openshift Cluster.
There are 4 types network tests:
1. pod to pod using Hostnetwork
2. pod to pod using SDN
3. pod to pod using Service
4. pod to pod using Multus (NetworkAttachmentDefinition needs to be provided)

Running from CLI:

```sh
pip3 install -r requirements.txt
$ ./run_<test-name>_network_test_fromgit.sh 
```

## Environment variables

### OPERATOR_REPO
Default: `https://github.com/cloud-bulldozer/benchmark-operator.git`    
Benchmark-operator repo that you want to clone

### OPERATOR_BRANCH
Default: `master`     
Branch name for benchmark-operator repo

### ES_SERVER
Default: `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443`
Elasticsearch server to index the results of the current run. Use the notation `http(s)://[username]:[password]@[address]:[port]` in case you want to use an authenticated ES instance.

### METADATA_COLLECTION
Default: `true`   
Enable/Disable collection of metadata

### SERVICETYPE
Default: `clusterip`  
Used only when `SERVICEIP` is set to `true` 
To provide specifics about openshift service types, supported options `clusterip`, `nodeport`, `metallb`   
`metallb` type requires manual installation of operators and configuration of BGPPeers as explained [here](https://github.com/cloud-bulldozer/benchmark-operator/blob/master/docs/uperf.md#advanced-service-types)

### ADDRESSPOOL
Default: `addresspool-l2`  
Used only when `SERVICETYPE` is `metallb`  
To provide MetalLB addresspool for a service, this will be used as LoadBalancer network.  
Mentioned addresspool should be pre-provisioned before execution of this script.  

### SERVICE_ETP
Default: `Cluster`  
Used only when `SERVICETYPE` is `metallb` 
To mention the type of `ExternalTrafficPolicy` of a service, supported option `Cluster` or `Local`

## Comparison

### COMPARE_WITH_GOLD
Default: ``     
If COMPARE is set to true and COMPARE_WITH_GOLD is set to true then the current run will be compared against our gold-index
Note: Make sure that elasticsearch baseline uuid (example: BASELINE_POD_1P_UUID, BASELINE_POD_2P_UUID ...) vars are not set or else it will override the uuids

### GOLD_SDN
Default: `openshiftsdn`   
Compares the current run with gold-index with the sdn type of GOLD_SDN. Options: `openshiftsdn` and `ovnkubernetes`

### ES_GOLD
Default: ``     
The ES server that houses gold-index. Format `http(s)://[username]:[password]@[address]:[port]`

### COMPARISON_ALIASES
Default:""
Benchmark-comparison aliases

### ES_SERVER_BASELINE 
Default: `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443`
Elasticsearch server used used by the baseline run. Format `http(s)://[username]:[password]@[address]:[port]`

> Setting either ES_GOLD or ES_SERVER_BASELINE, enables benchmark-comparison.

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

### COMPARISON_CONFIG
Default:`${PWD}/uperf-touchstone.json`
Benchmark-comparison configuration file

### COMPARISON_RC
Default: `0`
Benchmark-comparison return code if tolerancy check fails.

### TOLERANCY_RULES_CFG
Default: `uperf-tolerancy-rules.yaml`
Tolerancy rules configuration file

### CERBERUS_URL
Default: ``
URL to check the health of the cluster using Cerberus (https://github.com/cloud-bulldozer/cerberus).

### GSHEET_KEY_LOCATION
Default: *Commented out*      
The location where you placed your Google Service Account Key. ex: `$HOME/.secrets/gsheet_key.json`

### EMAIL_ID_FOR_RESULTS_SHEET
Default: *Commented out*       
For this you will have to place Google Service Account Key in the $GSHEET_KEY_LOCATION   
It will push your local results CSV to Google Spreadsheets and send an email with the attachment

### MULTI_AZ
Default: `true`
If true, uperf client and server pods will be colocated in different topology zones or AZs (`topology.kubernetes.io/zone` in k8s terminology).
You need at least 2 worker nodes placed in different in different topology zones to enable this flag.
If false, uperf client and server pods will be colocated in the same topology zone. You need at least 2 worker nodes in that topology zone.

### TEST_CLEANUP
Default: true
Remove benchmark CR at the end

### TEST_TIMEOUT
Default: 7200
Benchmark timeout in seconds


## Suggested configurations

```sh
export ES_SERVER=
export METADATA_COLLECTION=
export COMPARE_WITH_GOLD=
export GOLD_SDN=
export GOLD_OCP_VERSION=
export ES_GOLD=
export BASELINE_CLOUD_NAME=
export ES_SERVER_BASELINE=
export BASELINE_HOSTNET_UUID=
export BASELINE_POD_1P_UUID=
export BASELINE_POD_2P_UUID=
export BASELINE_POD_4P_UUID=
export BASELINE_SVC_1P_UUID=
export BASELINE_SVC_2P_UUID=
export BASELINE_SVC_4P_UUID=
export BASELINE_MULTUS_UUID=
export CERBERUS_URL=http://1.2.3.4:8080
#export GSHEET_KEY_LOCATION=
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key
```

## Snappy integration configurations
To backup data to a given snappy data-server

### Environment Variables

#### ENABLE_SNAPPY_BACKUP
Default: ''
Set to true to backup the logs/files generated during a workload run

#### SNAPPY_DATA_SERVER_URL
Default: ''
The Snappy data server url, where you want to move files.

#### SNAPPY_DATA_SERVER_USERNAME
Default: ''
Username for the Snappy data-server.

#### SNAPPY_DATA_SERVER_PASSWORD
Default: ''
Password for the Snappy data-server.

#### SNAPPY_USER_FOLDER
Default: 'perf-ci'
To store the data for a specific user

