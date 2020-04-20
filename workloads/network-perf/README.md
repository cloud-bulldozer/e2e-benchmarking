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

### ES_USER
Default: `` 
Username for elasticsearch instance

### ES_PASSWORD
Default: `` 
Password for elasticsearch instance

### ES_SERVER
Default: `milton.aws.com`  
Elasticsearch server to index the results of the current run

### ES_PORT
Default: ``  
Port number for elasticsearch server

### METADATA_COLLECTION
Default: `true`   
Enable/Disable collection of metadata

### COMPARE
Default: `false`   
Enable/Disable the ability to compare two uperf runs. If set to `true`, the next set of environment variables pertaining to the type of test are required

### ES_USER_BASELINE
Default: `` 
Username for elasticsearch instance

### ES_PASSWORD_BASELINE
Default: ``
Password for elasticsearch instance

### BASELINE_CLOUD_NAME
Default: ``    
Name you would like to give your baseline cloud. It will appear as a header in the CSV file

### ES_SERVER_BASELINE 
Default: ``   
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

### EMAIL_ID_FOR_RESULTS_SHEET
Default: *Commented out*       
For this you will have to place Google Service Account Key in /plow/workloads/network-perf dir.   
It will push your local results CSV to Google Spreadsheets and send an email with the attachment

## Suggested configurations

```sh
export ES_USER=
export ES_PASSWORD=
export ES_SERVER=
export ES_PORT=
export METADATA_COLLECTION=
export COMPARE=false
export BASELINE_CLOUD_NAME=
export ES_USER_BASELINE=
export ES_PASSWORD_BASELINE
export ES_SERVER_BASELINE=
export ES_PORT_BASELINE=
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
#export EMAIL_ID_FOR_RESULTS_SHEET=<your_email_id>  # Will only work if you have google service account key
```

