# Prometheus sizing benchmark

The scripts in this folder are meant to generate a workload that allow to measure the maximum Prometheus resource usage in a period of time.
According to docs, Prometheus WAL files (stored in wal directory in 128MiB segments) will retain at least 2 hours of raw data before rotatio & compaction. This WAL data is persisted in disk to be secured against crashes and stored in memory to improve query performance.

At the moment two different scenarios are being considered:

- Static scenario: Performed by `prometheus-sizing-static.sh`. This scenario fills all worker nodes across the cluster with 250 pods each, and then sleeps for `JOB_PAUSE`.
- Churning scenario: Performed by `prometheus-sizing-churning.sh`. This scenario generates pod churning across the worker nodes of the cluster. This pod churning consists of initally creating a certain number of namespaces in the cluster (this namespaces are holding a set of pods), and then delete and recreate each of those namespaces (with all its pods) each `POD_CHURNING_PERIOD`.

## Static scenario

Handled by the script `prometheus-sizing-churning.sh`, it can be customized with the following variables:

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **JOB_PAUSE**        | How long to wait before finishing the kube-burner job and index metrics | 125m |
| **QPS**              | Kube-burner's QPS                     | 40 |
| **BURST**              | Kube-burner's Burst rate            | 40 |
| **BURST**              | Kube-burner's Burst rate            | 40 |
| **CLEANUP_WHEN_FINISH** | Delete workload's namespaces after running it | false |
| **ENABLE_INDEXING**  | Enable/disable ES indexing      | true |
| **ES_SERVER**        | Elastic search endpoint         | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443 (You can disable indexing with `export ES_SERVER=""`)|
| **ES_INDEX**         | Elastic search index            | ripsaw-kube-burner |

## Churning scenario

Handled by the script `prometheus-sizing-churning.sh`, it can be customized with the following variables:

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **PODS_PER_NODE**    | How many pods to deploy in each node  | 50 |
| **POD_CHURNING_PERIOD**    | How often a namespace rotation  | 15m |
| **NUMBER_OF_NS**    | How many namespaces create             | 8 |
| **QPS**              | Kube-burner's QPS                     | 40 |
| **BURST**              | Kube-burner's Burst rate            | 40 |
| **BURST**              | Kube-burner's Burst rate            | 40 |
| **CLEANUP_WHEN_FINISH** | Delete workload's namespaces after running it | false |
| **ENABLE_INDEXING**  | Enable/disable ES indexing      | true |
| **ES_SERVER**        | Elastic search endpoint         | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443 (You can disable indexing with `export ES_SERVER=""`)|
| **ES_INDEX**         | Elastic search index            | ripsaw-kube-burner |

> Note: With the variables above, the total duration of the benchmark is given by `NUMBER_OF_NS * POD_CHURNING_PERIOD`.
