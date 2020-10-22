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

### ES_SERVER
Default: `http://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com:80`
Elasticsearch server to index the results of the current run. Use the notation `http(s)://[username]:[password]@[address]:[port]` in case you want to use an authenticated ES instance.

### METADATA_COLLECTION
Default: `true`   
Enable/Disable collection of metadata

### COMPARE
Default: `false`        
Enable/Disable the ability to compare two uperf runs. If set to `true`, the next set of environment variables pertaining to the type of test are required

### COMPARE_WITH_GOLD
Default: ``     
If COMPARE is set to true and COMPARE_WITH_GOLD is set to true then the current run will be compared against our gold-index
Note: Make sure that elasticsearch baseline uuid (example: BASELINE_POD_1P_UUID, BASELINE_POD_2P_UUID ...) vars are not set or else it will override the uuids

### GOLD_SDN
Default: `openshiftsdn`   
Compares the current run with gold-index with the sdn type of GOLD_SDN. Options: `openshiftsdn` and `ovnkubernetes`

### GOLD_OCP_VERSION
Default: ``     
The openshift version you want to compare the current run to

### ES_GOLD
Default: ``     
The ES server that houses gold-index. Format `http(s)://[username]:[password]@[address]:[port]`

### BASELINE_CLOUD_NAME
Default: ``    
Name you would like to give your baseline cloud. It will appear as a header in the CSV file

### ES_SERVER_BASELINE 
Default: `http://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com:80`
Elasticsearch server used used by the baseline run. Format `http(s)://[username]:[password]@[address]:[port]`

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

### CERBERUS_URL
Default: ``     
URL to check the health of the cluster using Cerberus (https://github.com/openshift-scale/cerberus).

### GSHEET_KEY_LOCATION
Default: *Commented out*      
The location where you placed your Google Service Account Key. ex: `$HOME/.secrets/gsheet_key.json`

### EMAIL_ID_FOR_RESULTS_SHEET
Default: *Commented out*       
For this you will have to place Google Service Account Key in the $GSHEET_KEY_LOCATION   
It will push your local results CSV to Google Spreadsheets and send an email with the attachment

## Suggested configurations

```sh
export ES_SERVER=
export METADATA_COLLECTION=
export COMPARE=false
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
export THROUGHPUT_TOLERANCE=5
export LATENCY_TOLERANCE=5
export CERBERUS_URL=http://1.2.3.4:8080
#export GSHEET_KEY_LOCATION=
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key
```

