# ocm-api-load e2e benchmarks

In order to kick off one of these benchmarks you must use the run.sh script.

Running from CLI:

```sh
$TESTS="list-clusters list-subscriptions" GATEWAY_URL="http://localhost:8080" OCM_TOKEN="notARealToken" RATE=10/s AWS_ACCESS_KEY_ID="empty" AWS_SECRET_ACCESS_KEY="empty" AWS_ACCOUNT_ID="empty" ./run.sh
```

## Dependencies

This workload requires awscli tool. Please install awscli before running this workload.


## Environment variables

Workloads can be tweaked with the following environment variables:


| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **OPERATOR_REPO**    | Benchmark-operator repo         | https://github.com/cloud-bulldozer/benchmark-operator.git      |
| **OPERATOR_BRANCH**  | Benchmark-operator branch       | master  |
| **ES_SERVER**        | Elasticsearch endpoint          | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | Elasticsearch index             | ripsaw-api-load|
| **TEST_TIMEOUT**        | Benchmark timeout, in seconds | 7200 (2 hours) |
| **TEST_CLEANUP**        | Remove benchmark CR at the end | true |
| **GATEWAY_URL**      | Gateway url to perform the test against       | "https://api.integration.openshift.com |
| **OCM_TOKEN**| OCM Authorization token |  |
| **AWS_ACCESS_KEY_ID**    | AWS access key          |  |
| **AWS_SECRET_ACCESS_KEY**              | AWS access secret                     |       |
| **AWS_ACCOUNT_ID**            | AWS Account ID, is the 12-digit account number |       |
| **SNAPPY_DATA_SERVER_URL**    | The Snappy data server url, where you want to move files          |  |
| **SNAPPY_DATA_SERVER_USERNAME**    | Username for the Snappy data-server          |  |
| **SNAPPY_DATA_SERVER_PASSWORD**    | Password for the Snappy data-server          |  |
| **RATE**| Rate of the attack. Format example 5/s | 10/s |
| **DURATION**         | Duration of each individual run in minutes | 1 |
| **OUTPUT_PATH** | Output directory for result and report files | /tmp/results |
| **COOLDOWN**         | Cooldown time between tests in seconds | 10 |
| **SLEEP**   |  | 5 |
| **TESTS** | Test names string i.e "list-clusters self-access-token list-subscriptions access-review register-new-cluster register-existing-cluster create-cluster get-current-account quota-cost resource-review cluster-authorizations self-terms-review certificates"| |

**Note**: You can use basic authentication for ES indexing using the notation `http(s)://[username]:[password]@[host]:[port]` in **ES_SERVER**.
Supported test names are "list-cluster self-access-token list-subscriptions access-review register-new-cluster register-existing-cluster create-cluster get-current-account quota-cost resource-review cluster-authorizations self-terms-review certificates"
Each test can be configured with specific rate and duration. For example, LIST_CLUSTERS_RATE and LIST_CLUSTERS_DURATION can be used to configure rate and duration for list-cluster test 
