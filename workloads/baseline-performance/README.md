 # Baseline Cluster Performance benchmark

The baseline performance benchmark is used to measure the performance metrics of the cluster when there are no resources loaded on the cluster. Helps in understanding the baseline performance of the control plane components, nodes, etcd, kubelet etc of Openshift. The baseline workload will sleep for ${WATCH_TIME} minutes and call kube-burner indexer to collect the metrics without loading the cluster.


## Common variables

These environment variables can be customized 

| Variable         | Description                         | Default |
|------------------|-------------------------------------|---------|
| **KUBE_BURNER_RELEASE_URL** | kube-burner tarball release location | `https://github.com/cloud-bulldozer/kube-burner/releases/download/v0.14.2/kube-burner-0.14.2-Linux-x86_64.tar.gz` |
| **WATCH_TIME**              | Sleep duration for which metrics will be collected in minutes| 30 |
| **ENABLE_INDEXING**  | Enable/disable ES indexing      | true |
| **ES_SERVER**        | ElasticSearch endpoint         | https://search-perfscale-dev-chmf5l4sh66lvxbnadi4bznl3a.us-west-2.es.amazonaws.com:443|
| **ES_INDEX**         | ElasticSearch index            | ripsaw-kube-burner |
| **WRITE_TO_FILE**     | Dump collected metrics to files  locally  | false |
