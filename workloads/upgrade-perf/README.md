# Upgrade Scripts

The purpose of the upgrade scripts is to upgrade an Openshift Cluster
to a given version. It will report the timings to Elasticsearch.

Running from CLI:

```sh
$ ./run_<test-name>_fromgit.sh 
```

## Environment variables

### VERSION
Default: ''
The version to upgrade to. The version must be on the list of previous or available updates.

### TOIMAGE
Default: ''
This is an optional location of an image to upgrade to.

### LATEST
Default: ''
Upgrades to the latest version available in the channel when set to true.

### CHANNEL
Channel to set for the upgrade to find the image to upgrade to, they can found at https://github.com/openshift/cincinnati-graph-data/blob/master/channels/.
Set CHANNEL=nightlies in case of upgrading to nightly builds which are not part of the upgrade path in cincinnati.
The channel set on the cluster is not tweaked if this variable is not set.

### POLL_INTERVAL
Default: 5
How long (in seconds) to have the test wait inbetween ready checks

### TIMEOUT
Default: 240
Timeout value (in minutes) for the upgrade. NOTE: there is no rollback on failure

### ES_SERVER
Default: `milton.aws.com`  
Elasticsearch server to index the results of the current run

### ES_PORT
Default: ``  
Port number for elasticsearch server

### COMPARE (not implemented yet)
Default: `false`   
Enable/Disable the ability to compare two runs. If set to `true`, the next set of environment variables pertaining to the type of test are required

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
URL to check the health of the cluster using Cerberus (https://github.com/cloud-bulldozer/cerberus).

## Suggested configurations

```sh
export ES_SERVER=
export ES_PORT=
export COMPARE=false
export BASELINE_CLOUD_NAME=
export ES_SERVER_BASELINE=
export ES_PORT_BASELINE=
export BASELINE_UUID=
export VERSION=
export TOVERSION=
export POLL_INTERVAL=
export TIMEOUT=
export CERBERUS_URL=http://1.2.3.4:8080
```

