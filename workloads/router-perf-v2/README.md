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

- podman
- pip install -r requirements.txt

## Configuration
It's possible to tune the default configuration through environment variables. They are described in the table below:


| Variable              | Description     | Default	          |
|-----------------------|-----------------|-------------------|
| KUBECONFIG            | Kubeconfig file | `~/.kube/config` |
| ENGINE                | Engine to spin up the local kube-burner container that creates the required infrastructure, if you set this to `local` it will try to download kube-burner binary locally using `KUBE_BURNER_RELEASE_URL` and use that instead of creating a container. | `podman` |
| RUNTIME               | Workload duration in seconds | `60` |
| TERMINATIONS          | List of HTTP terminations to test | `http edge passthrough reencrypt mix` |
| URL_PATH              | URL path to use in the benchmark | `/1024.html` |
| KEEPALIVE_REQUESTS    | List with the number of keep alive requests to perform in the same HTTP session | `0 1 50` |
| KUBE_BURNER_RELEASE_URL    | Used when ENGINE is set to `local`, ignored otherwise | `https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.9.1/kube-burner-0.9.1-Linux-x86_64.tar.gz` |
| LARGE_SCALE_THRESHOLD | Number of worker nodes required to consider a large scale scenario | `24` |
| SMALL_SCALE_ROUTES    | Number of routes of each termination to create in the small scale scenario | `100` |
| SMALL_SCALE_CLIENTS   | Threads/route to use in the small scale scenario | `1 40 200` |
| SMALL_SCALE_CLIENTS_MIX | Threads/route to use in the small scale scenario with mix termination | `1 20 80` |
| LARGE_SCALE_ROUTES    | Number of routes of each termination to create in the large scale scenario | `500` |
| LARGE_SCALE_CLIENTS   | Threads/route to use in the large scale scenario | `1 20 80` |
| LARGE_SCALE_CLIENTS_MIX | Threads/route to use in the large scale scenario with mix termination | `1 10 20` |
| TLS_REUSE             | Reuse TLS session | `true` |
| SAMPLES               | Number of samples to perform of each test | `2` |
| HOST_NETWORK          | Enable hostNetwork in the mb client | `true` |
| NUMBER_OF_ROUTERS     | Number of routers to test | `2` |
| NODE_SELECTOR         | Node selector of the mb client | `{node-role.kubernetes.io/workload: }` |
| QUIET_PERIOD          | Quiet period after each test iteration | `60s` |
| ES_SERVER             | Elasticsearch endpoint to send metrics | `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443` |
| ES_SERVER_BASELINE    | Elasticsearch endpoint used to fetch baseline results | "" |
| ES_INDEX              | Elasticsearch index | `router-test-results` |
| COMPARE               | Should we compare the gathered data to the baseline small/large scale UUIDs if provided | "false" |
| SMALL_SCALE_BASELINE_UUID | Baseline UUID to compare small scale results with (optional) | "" |
| LARGE_SCALE_BASELINE_UUID | Baseline UUID to compare large scale results with (optional) | "" |
| PREFIX                | Test name prefix (optional) | Result of `oc get clusterversion version -o jsonpath="{.status.desired.version}"` |
| SMALL_SCALE_BASELINE_PREFIX | Small scale baseline test name prefix (optional) | `baseline` |
| LARGE_SCALE_BASELINE_PREFIX | Large scale baseline test name prefix (optional) | `baseline` |
| GSHEET_KEY_LOCATION   | Path to service account key to generate google sheets (optional) | "" |
| EMAIL_ID_FOR_RESULTS_SHEET | It will push your local results CSV to Google Spreadsheets and send an email with the attachment (optional) | "" |
| SERVICE_TYPE          | K8S service type to use | `NodePort` |
| METADATA_COLLECTION   | Collect metadata prior to trigger the workload | `true` |

## Metrics

Each indexed document looks like:

```json
{
    "test_type": "mix",
    "termination": "mix",
    "uuid": "babdc414-09bd-4da1-815f-b95da239faa5",
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
The `env.sh` file is provided with all available configuration parameters. You can modify and source this file to tweak the workload.

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
