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

This folter contains two different variants:

- ingress-performance-small.sh (Meant to be used in clusters with 3 worker nodes):

The benchmark will create 100 routes of each termination. It will use `1 40 200` threads per target route for all terminations scenarios except `mix`.
The `mix` termination test consists of: 40 mixed routes (10 of each termination) with `1 40 200` threads per target route and another scenarios with 400 mixed routes (100 of each termination) with `1 20 80` threads per target route.

- ingress-performance-large.sh. (Meant to be used in clusters with 25 worker nodes):

The benchmark will create 500 routes of each termination. It will use `1 20 80` threads per target route for all terminations scenarios except `mix`.
The `mix` termination scenario consists of 200 mixed routes (50 of each termination) with `1 20 80` threads per target route and another scenario with 2000 mixed routes (500 of each termination) with `1 10 20` threads per target route.

---

This test uses a [python wrapper](workload.py) on top of mb. This wrapper takes care of executing mb with the passed configuration and index the results if `ES_SERVER` is set.

## Software requirements

Apart from the k8s/oc clients, running this script has several requirements:

- podman

## Configuration
It's possible to tune the default configuration through environment variables. They are described in the table below:


| Variable              | Description     | Default	          |
|-----------------------|-----------------|-------------------|
| KUBECONFIG            | Kubeconfig file | `~/.kube/config` |
| ENGINE                | Engine to spin up the local kube-burner container that creates the required infrastructure | `podman` |
| RUNTIME				| Workload duration in seconds | `120` |
| TERMINATIONS  		| List of HTTP terminations to test | `http edge passthrough reencrypt mix` |
| URL_PATH              | URL path to use in the benchmark | `/1024.html` |
| KEEPALIVE_REQUESTS	| List with the number of keep alive requests to perform in the same HTTP session | `1 40 200` |
| TLS_REUSE				| Reuse TLS session | `true` |
| SAMPLES				| Number of samples to perform of each test | `1` |
| HOST_NETWORK			| Enable hostNetwork in the mb client | `true` |
| NUMBER_OF_ROUTERS		| Number of routers to test | `2` |
| NODE_SELECTOR			| Node selector of the mb client | `{node-role.kubernetes.io/workload: }` |
| QUIET_PERIOD			| Quiet period after each test iteration | `60s` |
| ES_SERVER             | Elasticsearch endpoint to send metrics | `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443` |
| ES_SERVER_BASELINE    | Elasticsearch endpoint used to fetch baseline results | "" |
| ES_INDEX              | Elasticsearch index | `router-test-results` |
| BASELINE_UUID         | Baseline UUID to compare the results with (optional) | "" |
| PREFIX                | Test name prefix (optional) | Result of `oc get clusterversion version -o jsonpath="{.status.desired.version}"` |
| BASELINE_PREFIX       | Baseline test name prefix (optional) | `baseline` |
| GSHEET_KEY_LOCATION   | Path to service account key to generate google sheets (optional) | "" |
| EMAIL_ID_FOR_RESULTS_SHEET | It will push your local results CSV to Google Spreadsheets and send an email with the attachment (optional) | "" |
| THROUGHPUT_TOLERANCE  | Accepeted deviation in percentage for throughput when compared to a baseline run | 5 |
| LATENCY_TOLERANCE     | Accepeted deviation in percentage for latency when compared to a baseline run | 5 |
| SERVICE_TYPE          | K8S service type to use | `NodePort` |

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
