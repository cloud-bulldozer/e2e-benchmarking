# Ingress controller performance

The purpose of the `ingress-performance.sh` script is to run an e2e ingress benchmark suite against the given OpenShift cluster.

# Workload behaviour
This script uses kube-burner to quickly spin-up the required infrastructure to perform the benchmark.
The different test scenarios are performed in order according to the following logic.

```
for clients in CLIENTS; do
  for keepalive_requests in KEEPALIVE_REQUESTS; do
    for termination in TERMINATIONS; do
      for sample in SAMPLES; do
        run_test
      done
    done
  done
done
```

This test uses a [python wrapper](workload.py) on top of mb. This wrapper takes care of executing mb with the passed configuration and index the results if `ES_SERVER` is set.

## Software requirements

Apart from the k8s/oc clients, running this script has several requirements:

- jq
- podman

## Configuration
It's possible to tune the default configuration through environment variables. They are described in the table below:


| Variable              | Description     | Default	          |
|-----------------------|-----------------|-------------------|
| KUBECONFIG            | Kubeconfig file | `-~/.kube/config` |
| ENGINE                | Engine to spin up the local kube-burner container that creates the required infrastructure | `podman` |
| RUNTIME				| Workload duration in seconds | `120` |
| TERMINATION			| List of HTTP terminations to test | `http edge passthrough reencrypt mix` |
| URL_PATH              | URL path to use in the benchmark | `/1024.html` |
| NUMBER_OF_ROUTES		| Number of routes of each termination to test. (the mix scenario test all of them together | `100` |
| KEEPALIVE_REQUESTS	| List with the number of keep alive requests to perform in the same HTTP session | `1 40 200` |
| CLIENTS				| List with the number of clients (threads per target route) | `1 10 100`|
| TLS_REUSE				| Reuse TLS session | `true` |
| RAMP_UP				| Ramp-up period | `0 ` |
| SAMPLES				| Number of samples to perform of each test | `1` |
| HOST_NETWORK			| Enable hostNetwork in the mb client | `true` |
| NUMBER_OF_ROUTERS		| Number of routers to test | `2` |
| NODE_SELECTOR			| Node selector of the mb client | `{"node-role.kubernetes.io/workload": ""}` |
| QUIET_PERIOD			| Quiet period after each test iteration | `10s` |
| ES_SERVER             | Elasticsearch endpoint to send metrics | `https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443` |
| ES_INDEX              | Elasticsearch index | `router-test-results` |

## Metrics

Each indexed document looks like:

```json
{
    "termination": "mix",
    "uuid": "babdc414-09bd-4da1-815f-b95da239faa5",
    "requests_per_second": 58529,
    "latency_95pctl": 377226,
    "latency_99pctl": 1198476,
    "host_network": "true",
    "sample": "2",
    "runtime": 30,
    "ramp_up": 0,
    "routes": 40,
    "threads_per_target": 200,
    "keepalive_requests": 10,
    "tls_reuse": false,
    "200": 1755889,
    "0": 17
}
```
