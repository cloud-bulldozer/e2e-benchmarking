# Ingress-perf

The `./run.sh` script is just a small wrapper on top of [ingress-perf](https://github.com/cloud-bulldozer/ingress-perf) to be used as entrypoint of some of its flags.

In order to run a test you have to set the `CONFIG` environment variable pointing to one of the configuration files available in the [config directory](config/) and just issue `./run.sh`. i.e:

```shell
$ CONFIG=config/standard.yml ./run.sh
time="2023-05-23 12:17:54" level=info msg="Running ingress performance adbddaf1-2a9e-4c53-a410-f98749fd901e" file="ingress-perf.go:41"
time="2023-05-23 12:17:54" level=info msg="Creating elastic indexer" file="ingress-perf.go:49"
time="2023-05-23 12:17:56" level=info msg="Starting ingress-perf" file="runner.go:42"
time="2023-05-23 12:18:00" level=info msg="Deploying benchmark assets" file="runner.go:148"
time="2023-05-23 12:18:02" level=info msg="Running test 1/1: http" file="runner.go:73"
time="2023-05-23 12:18:06" level=info msg="Running sample 1/3: 5s" file="exec.go:65"
time="2023-05-23 12:18:17" level=info msg="Summary: Rps=36212.07 req/s avgLatency=108545.60 μs P99Latency=273390.30 μs" file="exec.go:72"
time="2023-05-23 12:18:17" level=info msg="Running sample 2/3: 5s" file="exec.go:65"
time="2023-05-23 12:18:26" level=info msg="Summary: Rps=39225.47 req/s avgLatency=107981.03 μs P99Latency=436042.60 μs" file="exec.go:72"
time="2023-05-23 12:18:26" level=info msg="Running sample 3/3: 5s" file="exec.go:65"
...
```

## Environment variables

This wrapper supports some variables to tweak some basic parameters of the workloads:

- **CONFIG**: Defines the configuration file to use. Configuration files are available in the [config directory](config/).
- **ES_SERVER**: Defines the ElasticSearch/OpenSearch endpoint. By default it points the development instance.
- **ES_INDEX**: Defines the ElasticSearch/OpenSearch index. By default `ingress-performance`
- **LOG_LEVEL**: Defines the loglevel, by default `info`

## Results comparison environment variables

Ingress-perf is able to compare the benchmark results with a provided UUID, this is useful to detect performance regressions.
This fature can be customized using the following vars

- **BASELINE_UUID**: Defines a baseline UUID to compare the workload with. Filling this variable enables the comparison feature.
- **BASELINE_INDEX**: Defines the index where the baseseline benchmark results are. By default `ingress-performance-baseline`
- **TOLERANCY**: Defines a regression tolerancy percent. By default `20`

## Workloads documentation

More extensive documentation about how to build a workload can be found at the [project's landing page](https://github.com/cloud-bulldozer/ingress-perf)

