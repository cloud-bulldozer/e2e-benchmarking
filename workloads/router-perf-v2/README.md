# Ingress controller performance

The purpose of the `ingress-performance.sh` script is to run an e2e ingress benchmark suite against the given OpenShift cluster.

# Workload behaviour
These scripts use kube-burner to quickly spin-up the required infrastructure to perform the benchmark.
The different test scenarios are performed in order according to the following pseudo-code.

```
for termination in TERMINATIONS; do
  for clients in CLIENTS; do
    for keepalive_requests in KEEPALIVE_REQUESTS; do
      for sample in SAMPLES; do
        run_test
        sleep QUIER_PERIOD
      done
    done
  done
done
```

Note: The number of clients used for the mix termination is configured by a different variable since this scenario benchmarks the different terminations all together.

---

This test uses a [python wrapper](workload.py) on top of mb. This wrapper takes care of executing mb with the passed configuration and index the results if `ES_SERVER` is set.

## Software requirements

Apart from the k8s/oc clients, running this script has several requirements:

- python3.6 (Required for benchmark-comparison)

## Configuration
It's possible to tune the default configuration through environment variables. They are described in the table below:


| Variable              | Description     | Default	          |
|-----------------------|-----------------|-------------------|
| KUBECONFIG            | Kubeconfig file | `~/.kube/config` |
| RUNTIME               | Workload duration in seconds | `60` |
| TERMINATIONS          | List of HTTP terminations to test | `http edge passthrough reencrypt mix` |
| URL_PATH              | URL path to use in the benchmark | `/1024.html` |
| KEEPALIVE_REQUESTS    | List with the number of keep alive requests to perform in the same HTTP session | `0 1 50` |
| KUBE_BURNER_RELEASE_URL    | Kube-burner binary URL | `https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.15.4/kube-burner-0.15.4-Linux-x86_64.tar.gz` |
| LARGE_SCALE_THRESHOLD | Number of worker nodes required to consider a large scale scenario | `24` |
| SMALL_SCALE_ROUTES    | Number of routes of each termination to create in the small scale scenario | `100` |
| SMALL_SCALE_CLIENTS   | Threads/route to use in the small scale scenario | `1 40 200` |
| SMALL_SCALE_CLIENTS_MIX | Threads/route to use in the small scale scenario with mix termination | `1 20 80` |
| LARGE_SCALE_ROUTES    | Number of routes of each termination to create in the large scale scenario | `500` |
| LARGE_SCALE_CLIENTS   | Threads/route to use in the large scale scenario | `1 20 80` |
| LARGE_SCALE_CLIENTS_MIX | Threads/route to use in the large scale scenario with mix termination | `1 10 20` |
| DEPLOYMENT_REPLICAS   | Number of replicas per deployment when using deployments rather than pods | `10` |
| TLS_REUSE             | Reuse TLS session | `true` |
| SAMPLES               | Number of samples to perform of each test | `2` |
| HOST_NETWORK          | Enable hostNetwork in the mb client | `true` |
| NUMBER_OF_ROUTERS     | Number of routers to test | `2` |
| NODE_SELECTOR         | Node selector of the mb client | `{node-role.kubernetes.io/workload: }` |
| QUIET_PERIOD          | Quiet period after each test iteration | `60s` |
| ES_SERVER             | Elasticsearch endpoint to send metrics | `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443` |
| ES_INDEX              | Elasticsearch index | `router-test-results` |
| SERVICE_TYPE          | K8S service type to use | `NodePort` |
| METADATA_COLLECTION   | Collect metadata prior to trigger the workload | `true` |
| HAPROXY_IMAGE         | Variable to override the default HAProxy container image | unset |
| INGRESS_OPERATOR_IMAGE     | Variable to override the default ingress-operator container image | unset |

### Benchmark-comparison variables:

The ingress-performance script is able to invoke benchmark-comparison to perform results comparisons and then generate a google spreadsheet document. If `ES_SERVER_BASELINE` is not set, benchmark-comparison is used to generate a CSV results file.


| Variable              | Description     | Default	          | Required |
|-----------------------|-----------------|-------------------|---------------------------------|
| ES_SERVER_BASELINE    | Elasticsearch endpoint used to fetch baseline results | "" | no |
| BASELINE_UUID         | UUID of the benchmark to use as baseline in comparison | "" | no | 
| COMPARISON_CONFIG     | Benchmark-comparison configuration file | `${PWD}/mb-touchstone.json` | no |
| COMPARISON_ALIASES    | Benchmark-comparison aliases       | "" | no |
| COMPARISON_OUTPUT_CFG | Benchmark-comparison output file   | `${PWD}/ingress-performance.csv`| no |
| COMPARISON_RC         | Benchmark-comparison return code if tolerancy check fails | 0 | no |
| TOLERANCY_RULES_CFG   | Tolerancy rules configuration file | `{PWD}/mb-tolerancy-rules.yaml` | no |
| GSHEET_KEY_LOCATION   | Path to service account key to generate google sheets (optional) | "" | no |
| EMAIL_ID_FOR_RESULTS_SHEET | It will push your local results CSV to Google Spreadsheets and send an email with the attachment | "" | no |


## Metrics

Indexed documents look like:

```json
{
    "test_type": "mix",
    "termination": "mix",
    "uuid": "babdc414-09bd-4da1-815f-b95da239faa5",
    "cluster.id": "0d7ce156-90d7-4f87-a4e1-d0553151e78f",
    "cluster.name": "some-cluster",
    "cluster.ocp_version": "4.9.12",
    "cluster.kubernetes_version": "1.22",
    "cluster.type": "rosa",
    "cluster.sdn": "OpenShiftSDN",
    "cluster.platform": "AWS",
    "requests_per_second": 58529,
    "avg_latency": 477226,
    "latency_95pctl": 377226,
    "latency_99pctl": 1198476,
    "host_network": "true",
    "sample": "2",
    "runtime": 30,
    "routes": 40,
    "threads_per_target": 200,
    "keepalive": 10,
    "tls_reuse": false,
    "200": 1755889,
    "0": 17,
    "number_of_routers": 1
}
```

## Configuration file
The `env.sh` file is provided with all available configuration parameters. You can modify this file or export environment variables to tweak the workload.

## Snappy integration configurations
To backup data to a given snappy data-server

### Environment Variables

#### ENABLE_SNAPPY_BACKUP
Default: ''
Set to true to backup the logs/files generated during a workload run

#### SNAPPY_DATA_SERVER_URL
Default: ''
The Snappy data server url, where you want to move files.

#### SNAPPY_DATA_SERVER_USERNAME
Default: ''
Username for the Snappy data-server.

#### SNAPPY_DATA_SERVER_PASSWORD
Default: ''
Password for the Snappy data-server.

#### SNAPPY_USER_FOLDER
Default: 'perf-ci'
To store the data for a specific user
