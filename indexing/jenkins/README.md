# INDEXER
Indexes jenkins job information and status into elasticsearch

## RUN

```
Usage: export <options> ./index.sh

Options supported, export them as environment variables:
	ES_SERVER=str,                    str=elasticsearch server url, default: 
	ES_INDEX=str,                     str=elasticsearch index, default: perf_scale_ci
	JENKINS_USER=str,                 str=Jenkins user, default: 
	JENKINS_API_TOKEN=str,            str=Jenkins API token to authenticate, default: 
	JENKINS_BUILD_TAG=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in Jenkins environment
	JENKINS_NODE_NAME=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in Jenkins environment
	JENKINS_BUILD_URL=str,            str=jenkins job build url, it's a built-in env var and is automatically set in Jenkins environment
	BENCHMARK_STATUS_FILE=str,        str=path to the file with benchmark status reported using key=value pairs, default:
```
