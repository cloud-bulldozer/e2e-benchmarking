# Scale Scripts

The purpose of the scale scripts is scale Openshift Cluster to a given size.
It will scale up and down X number of times and report the timings to 
Elasticsearch

Running from CLI:

```sh
$ ./run_<test-name>_fromgit.sh 
```

## Environment variables

### SCALE
Default: ''
The target scale of the workers in the cluster. THIS IS A REQUIRED VARIABLE

### POLL_INTERVAL
Default: 5
How long (in seconds) to have the scale test wait inbetween ready checks

### POST_SLEEP
Default: 0
How long to have the system wait after a scale event

### TIMEOUT
Default: 240
Timeout value (in minutes) for each scale event

### RUNS
Default: 3
How many times to run the scale up. It will scale down to the original size before running the next itteration

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
Default: `false`   
Enable/Disable collection of metadata

### COMPARE (not implemented yet)
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

### BASELINE_UUID
Default: ``   
Baseline UUID 

### CERBERUS_URL
Default: ``     
URL to check the health of the cluster using Cerberus (https://github.com/openshift-scale/cerberus).

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
export BASELINE_UUID=
export CERBERUS_URL=http://1.2.3.4:8080
export SCALE=
export POLL_INTERVAL=
export POST_SLEEP=
export TIMEOUT=
export RUNS=
```

