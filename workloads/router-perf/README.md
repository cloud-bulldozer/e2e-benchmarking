# Router Script

The purpose of the router script is to run e2e router workload on the Openshift Cluster.

Running from CLI:    
First make changes to `env.sh` according to the the env vars mentioned here https://github.com/openshift-scale/workloads/blob/master/docs/http.md and below
```sh
pip3 install -r requirements.txt
$ ./run_router_test.sh 
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

### COMPARE
Default: `false`    
Enable/Disable the ability to compare two uperf runs. If set to `true`, the next set of environment variables pertaining to the type of test are required

### COMPARE_WITH_GOLD
Default: ``     
If COMPARE is set to true and COMPARE_WITH_GOLD is set to true then the current run will be compared against our gold-index
Note: Make sure that elasticsearch baseline uuid (example: BASELINE_ROUTER_UUID) vars are not set or else it will override the uuids

### GOLD_SDN
Default: `you current cluster's sdn`   
Compares the current run with gold-index with the sdn type of GOLD_SDN. Options: `openshiftsdn` and `ovnkubernetes`

### GOLD_OCP_VERSION
Default: ``     
The openshift version you want to compare the current run to

### ES_GOLD
Default: ``     
The ES server that houses gold-index. Format `user:pass@<es_server>:<es_port>

### ES_USER_BASELINE
Default: ``             
Username for elasticsearch instance

### ES_PASSWORD_BASELINE
Default: ``               
Password for elasticsearch instance

### ES_SERVER_BASELINE 
Default: ``    
Elasticsearch server used used by the baseline run 

### ES_PORT_BASELINE
Default: `80`   
Port number for the elasticsearch server used by the baseline run

### BASELINE_ROUTER_UUID
Default: ``    
Baseline UUID for router test  

### BASELINE_CLOUD_NAME
Default: ``               
Name you would like to give your baseline cloud. It will appear as a header in the CSV file

### THROUGHPUT_TOLERANCE
Default: `5`   
Accepeted deviation in percentage for throughput when compared to a baseline run

### LATENCY_TOLERANCE
Default: `5`   
Accepeted deviation in percentage for latency when compared to a baseline run

### CERBERUS_URL
Default: ``     
URL to check the health of the cluster using Cerberus (https://github.com/openshift-scale/cerberus)

### GSHEET_KEY
Default: *Commented out*               
Service account key to generate google sheets

### GSHEET_KEY_LOCATION
Default: *Commented out*              
Path to service account key to generate google sheets

### EMAIL_ID_FOR_RESULTS_SHEET
Default: *Commented out*        
It will push your local results CSV to Google Spreadsheets and send an email with the attachment

## Suggested configurations for a smoke test

```sh
export PBENCH_SERVER=''
export COMPARE=false
export HTTP_TEST_SUFFIX='smoke-test'
export HTTP_TEST_SMOKE_TEST=true
```

