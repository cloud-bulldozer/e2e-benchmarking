# SDN to OVNK migration Scripts

The script helps to Migrate an existing cluster default CNI from OpenShiftSDN to OVNKubernetes.
Tested only on Self Managed clusters and script does not take any backup or roll back incase of failure.
This script captures time taken for a successful rollout to MCO and time taken to cluster IP assignment to
pods in OVN-Kubernetes

Running from CLI:

```sh
$./run.sh
```

## Workload variables

The run.sh script can be tweaked with the following environment variables.
NOTE: can be bumped upto 10% of total worker nodes while performing a Loaded CNI Migration

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| **MAX_UNAVAILABLE_WORKER**  | Maximum allowed unavailable worker node limit | 1 |
