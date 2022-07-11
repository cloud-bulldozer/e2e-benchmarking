# Hypershift perfscale Scripts

The purpose of the script is to install Hypershift Operator on an Openshift cluster and create HostedCluster workload on them.

1. Install and create cluster: `./run.sh build`
2. Cleanup clusters: `./run.sh clean`


Running from CLI:

```sh
$./run.sh build
```

## Workload variables

The run.sh script can be tweaked with the following environment variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| **AWS_REGION**            | AWS region where the management cluster lives on | `us-west-2` |
| **AWS_ACCESS_KEY_ID**       | AWS access key for authentication | **REQUIRED** |
| **AWS_SECRET_ACCESS_KEY**     | AWS secret for authentication | **REQUIRED** |
| **ROSA_ENVIRONMENT**           | ROSA environment, `staging` or `production`, but at the moment hypershift isn't available on production so only supported environment is `staging`  | `staging` |
| **ROSA_TOKEN** | ROSA token for access, only staging account token is valid currently | **REQUIRED** |
| **PULL_SECRET**   | Cloud pull secret for Openshift installation  | **REQUIRED** |
| **NUMBER_OF_HOSTED_CLUSTER**         | Integer: number of hosted cluster to be deployed on given management cluster | `2` |
| **COMPUTE_WORKERS_NUMBER**         | Integer: number of workers nodes to be created on each hosted cluster | `24` |
| **NETWORK_TYPE**         | Network type of the hosted cluster, only supported value is OpenShiftSDN | `OpenShiftSDN` |
| **REPLICA_TYPE**             | Hosted control plane availability, supported values are `HighlyAvailable`, `SingleReplica` | `HighlyAvailable` |
| **COMPUTE_WORKERS_TYPE**            | AWS instance type of the workers to be used | `m5.4xlarge` |
| **HYPERSHIFT_OPERATOR_VERSION**    | The Hypershift operator version image | `quay.io/hypershift/hypershift-operator:latest` |
| **RELEASE_IMAGE**    | The OCP release image for the hostedcluster, ex: `quay.io/openshift-release-dev/ocp-release:4.10.5-x86_64` |  |
| **CPO_IMAGE** | Custom control plane operator image ex: `quay.io/hypershift/hypershift:latest` |  |
| **HYPERSHIFT_CLI_INSTALL**         | Boolean: to install/re-install hypershift CLI  | `true` |
| **HYPERSHIFT_CLI_VERSION**         | Version of hypershift CLI, branch name of the fork | `master` |
| **HYPERSHIFT_CLI_FORK**         | Github source url of hypershift CLI | https://github.com/openshift/hypershift |
| **ENABLE_INDEX**             | Boolean: To index management cluster stats during HostedCluster creation | `true` |
| **ES_SERVER**            | ElasticSearch server url | |
| **ES_INDEX**    | ElasticSearch Index to be used | `ripsaw-kube-burner` |
| **THANOS_QUERIER_URL** | Thanos querier url endpoint or management cluster prometheus public endpoint  |  |
