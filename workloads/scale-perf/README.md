# Scale Scripts

The purpose of the scale scripts is scale Openshift Cluster to a given size.
It will scale up and down X number of times and report the timings to
Elasticsearch

Running from CLI:

```sh
$ ./run_<test-name>_fromgit.sh
```

## Environment variables

### OPERATOR_REPO
Default: `https://github.com/cloud-bulldozer/benchmark-operator.git`  

Benchmark-operator repo that you want to clone

### OPERATOR_BRANCH
Default: `master`     
Branch name for benchmark-operator repo

### SCALE
Default: ''

The target scale of the workers in the cluster. THIS IS A REQUIRED VARIABLE

### WORKLOAD_NODE_ROLE
Default : worker

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

How many times to run the scale up. It will scale down to the original size before running the next iteration

### ES_SERVER
Default: `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443`

Elasticsearch server to index the results of the current run. Use the notation `http(s)://[username]:[password]@[address]:[port]` in case you want to use an authenticated ES instance.

### METADATA_COLLECTION
Default: `false`   
Enable/Disable collection of metadata

### CERBERUS_URL
Default: ''

URL to check the health of the cluster using Cerberus (https://github.com/cloud-bulldozer/cerberus).

## ROSA Integration
Default: ''

When scaling clusters installed on ROSA, following variables are also required:

### ROSA_CLUSTER_NAME
Default: ''

Cluster Name as it is shown when running `rosa list clusters`

### ROSA_ENVIRONMENT
Default: ''

Environment where cluster is deployed (Production, Staging)

### ROSA_TOKEN
Default: ''

Token used to login on ROSA

### AWS_ACCESS_KEY_ID
Default: ''

AWS Key to access AWS

### AWS_SECRET_ACCESS_KEY
Default: ''

AWS Secret Key to access AWS

### AWS_DEFAULT_REGION
Default: ''

AWS Region

### TEST_CLEANUP
Default: true
Remove benchmark CR at the end

### TEST_TIMEOUT
Default: 3600
Benchmark timeout in seconds

## Suggested configurations

```sh
export ES_SERVER=
export METADATA_COLLECTION=
export CERBERUS_URL=http://1.2.3.4:8080
export SCALE=
export POLL_INTERVAL=
export POST_SLEEP=
export TIMEOUT=
export RUNS=
```
