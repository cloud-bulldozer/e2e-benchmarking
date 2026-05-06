# k8s-io FIO

Wrapper for [k8s-io](https://github.com/jtaleric/k8s-io), a lightweight CLI tool for running distributed FIO benchmarks on Kubernetes/OpenShift clusters.

## Running from CLI

```sh
$ ./run.sh
```

This runs the smoke test (`smoke.yaml`) — a single FIO server, 1 sample, read-only with 4KiB block size.

```sh
$ CONFIG=full-run.yaml ./run.sh
```

This runs a comprehensive FIO benchmark with multiple job types (read, write, randread, randwrite), block sizes (4KiB, 8KiB, 16KiB), 3 servers, and 3 samples.

### Custom configuration

Point `CONFIG` to any k8s-io FIO config file:

```sh
$ CONFIG=/path/to/my-config.yaml ./run.sh
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| CLEANUP | Clean up resources created by k8s-io after the benchmark | `true` |
| CONFIG | k8s-io YAML configuration file | `smoke.yaml` |
| ES_SERVER | Elasticsearch/OpenSearch endpoint for CI metadata indexing | unset |
| ES_INDEX | Elasticsearch/OpenSearch index name | `ripsaw-fio` |
| K8S_IO_URL | URL to download k8s-io | `https://github.com/jtaleric/k8s-io/releases/download/${K8S_IO_VERSION}/k8s-io_${OS}_${K8S_IO_VERSION}_${ARCH}.tar.gz` |
| K8S_IO_VERSION | k8s-io tag/version | `v0.1.0` |
| OS | System to run k8s-io | `Linux` |
| TEST_TIMEOUT | Timeout for the benchmark in seconds | `14400` |
| UUID | UUID for the workload run | `uuidgen` |
| WORKLOAD | Workload name used for indexing | `k8s-io` |
