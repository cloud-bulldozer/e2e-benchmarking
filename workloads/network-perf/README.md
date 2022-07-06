# Network Scripts

The purpose of the network scripts is to run uperf workload on the Openshift Cluster.
There are 5 types network tests:

1. pod to pod using SDN: `WORKLOAD=pod2pod ./run.sh`
2. pod to pod using SDN and network policy: `WORKLOAD=pod2pod NETWORK_POLICY=true ./run.sh`
3. pod to pod using Hostnetwork: `WORKLOAD=hostnet ./run.sh`
4. pod to service: `WORKLOAD=pod2svc ./run.sh`
5. pod to service and network policy: `WORKLOAD=pod2svc NETWORK_POLICY=true ./run.sh`
6. pod to pod using Multus (NetworkAttachmentDefinition needs to be provided): `./run_multus_network_tests_fromgit.sh`

Running from CLI:

```sh
$./run.sh
```

## Workload variables

The run.sh script can be tweaked with the following environment variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| **WORKLOAD**            | Networking workload, can be either pod2pod, pod2pod, hostnet or, smoke | smoke |
| **OPERATOR_REPO**       | Benchmark-operator repo                     | https://github.com/cloud-bulldozer/benchmark-operator.git |
| **OPERATOR_BRANCH**     | Benchmark-operator branch                     | master      |
| **ES_SERVER**           | Elasticsearch endpoint         | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443 |
| **METADATA_COLLECTION** | Enable metadata collection | true (If indexing is disabled metadata collection will be also disabled) |
| **METADATA_TARGETED**   | Enable metadata targeted collection | false |
| **NETWORK_POLICY**      | If enabled, benchmark-operator will create a network policy to allow ingress trafic in uperf server pods | false |
| **SERVICETYPE**         | To provide specifics about openshift service types, supported options `clusterip`, `nodeport`, `metallb`. `metallb` type requires manual installation of operators and configuration of BGPPeers as explained [here](https://github.com/cloud-bulldozer/benchmark-operator/blob/master/docs/uperf.md#advanced-service-types) | clusterip |
| **ADDRESSPOOL**         | To provide MetalLB addresspool for a service, this will be used as LoadBalancer network. Mentioned addresspool should be pre-provisioned before execution of this script. | addresspool-l2 |
| **SERVICE_ETP**         | To mention the type of `ExternalTrafficPolicy` of a service, supported option `Cluster` or `Local` | Cluster |
| **SAMPLES**             | How many times to run the tests | 3 |
| **MULTI_AZ**            | If true, uperf client and server pods will be colocated in different topology zones or AZs (`topology.kubernetes.io/zone` in k8s terminology). 2 worker nodes in differet topology zones are required to enable this flag.  If false, uperf client and server pods will be colocated in the same topology zone | true |
| **PAIRS**               | List with the number of pairs the test will be triggered (hostnet variant is executed w/ 1 pair only) | 1 2 4 |
| **TEST_TIMEOUT**        | Benchmark timeout, in seconds | 7200 (2 hours) |
| **TEST_CLEANUP**        | Remove benchmark CR at the end | true |


## Comparison

The environment variables below are used to configure benchmark comparison and/or result reporting

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| **COMPARISON_ALIASES**  | Benchmark-comparison aliases (UUIDs will be replaced by these aliases | "" |
| **ES_SERVER_BASELINE**  | Elasticsearch endpoint used used by the baseline benchmark | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443 |
| **BASELINE_UUID**       | Baseline UUID used for comparison | "" |
| **COMPARISON_CONFIG**   | Benchmark-comparison config file | `${PWD}/uperf-touchstone.json` |
| **COMPARISON_RC**       | Benchmark-comparison return code if tolerancy check fails | 0 |
| **TOLERANCY_RULES_CFG** | Tolerancy rules configuration file | uperf-tolerancy-rules.yaml |
| **GSHEET_KEY_LOCATION** | Location of the Google Service Account Key, used to import a resulting csv | "" |
| **EMAIL_ID_FOR_RESULTS_SHEET**   | Email to push CSV results | "" |
| **GEN_CSV**             | Generate a benchmark-comparison csv, required to generate the spreadsheet | "false" |

## Snappy integration configurations

To backup data to a given snappy data-server

### Environment Variables

| Variable                | Description              | Default |
|-------------------------|--------------------------|---------|
| **ENABLE_SNAPPY_BACKUP**  | Set to true to backup the logs/files generated during a workload run | "" |
| **SNAPPY_DATA_SERVER_URL**  | The Snappy data server url, where you want to move files | "" |
| **SNAPPY_DATA_SERVER_USERNAME**  | The Snappy data server url, where you want to move files | "" |
| **SNAPPY_DATA_SERVER_PASSWORD**  |  Password for the Snappy data-server | "" |
| **SNAPPY_USER_FOLDER**  | To store the data for a specific user | perf-ci |
