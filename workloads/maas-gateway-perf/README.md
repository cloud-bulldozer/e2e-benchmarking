# MaaS Gateway Performance Benchmark

This workload measures the latency and throughput overhead of the MaaS (Models-as-a-Service) AI Gateway on OpenShift. It runs A/B tests comparing direct-to-simulator performance (baseline) against gateway-routed performance across multiple AI providers, payload sizes, and concurrency levels.

GuideLLM benchmarks run as native Kubernetes Jobs created by kube-burner-ocp. The `ghcr.io/cloud-bulldozer/guidellm-results-parser` container image includes both GuideLLM and the results parser, which indexes results directly to OpenSearch. No external scripts or pip installs are needed at benchmark time.

## Prerequisites

- An OpenShift cluster (4.19.9+) with cluster-admin access
- `oc` CLI configured and authenticated
- Network access to GitHub (for downloading kube-burner-ocp and cloning the MaaS repo)
- OperatorHub access (the MaaS deploy script installs operators via OLM)

## How It Works

```
run.sh
  Phase 1: Download kube-burner-ocp binary
  Phase 2: Deploy MaaS platform (deploy.sh --operator-type odh|rhoai)
           Installs: cert-manager, LWS, Kuadrant/RHCL, ODH/RHOAI operator,
                     DSC, PostgreSQL, Gateway, MaaS controller, maas-api
  Phase 3: Discover gateway and simulator endpoints
  Phase 4: Run kube-burner-ocp maas-gateway-perf
           Job 1: Deploy test infra (simulator, ExternalModels, HTTPRoutes, Secrets)
           Jobs 2..N: GuideLLM K8s Jobs — baseline A/B pairs per provider/payload/concurrency
           Jobs N+1..2N: GuideLLM K8s Jobs — gateway A/B pairs
           Last job: Cleanup
  Phase 5: Copy collected metrics to artifact directory
  Phase 6: Index CI metadata via utils/index.sh
```

The kube-burner job config uses Go template loops over providers, payload sizes, and concurrency levels to generate all benchmark jobs dynamically from CLI flags.

## Usage

Basic usage with defaults (ODH, 2 providers, 2 payload sizes, 5 concurrency levels = 20 baseline + 20 gateway = 40 GuideLLM Jobs):

```shell
$ ./run.sh
```

Full 5-provider matrix with RHOAI:

```shell
$ OPERATOR_TYPE=rhoai \
  PROVIDERS="gpt-4o-openai,gpt-4o-azure,gpt-4o-bedrock,claude-sonnet-anthropic,claude-sonnet-vertex" \
  PAYLOAD_SIZES="small,medium,large,very-large" \
  CONCURRENCY_LEVELS="8,32,64,128,512" \
  ./run.sh
```

Quick smoke test (1 provider, 1 payload, 2 concurrency levels):

```shell
$ PROVIDERS="gpt-4o-openai" \
  PAYLOAD_SIZES="small" \
  CONCURRENCY_LEVELS="8,64" \
  BENCHMARK_DURATION=30 \
  WARMUP=10 \
  ./run.sh
```

With OpenSearch indexing:

```shell
$ ES_SERVER=https://USER:PASSWORD@HOSTNAME:443 \
  OPERATOR_TYPE=odh \
  ./run.sh
```

## Environment Variables

### Platform

| Variable | Description | Default |
|----------|-------------|---------|
| `OPERATOR_TYPE` | Operator to deploy: `odh` or `rhoai`. Determines the full stack (operator, policy engine, namespaces) | `odh` |
| `MAAS_REF` | Git tag/branch of `opendatahub-io/models-as-a-service` to deploy | `v2.0.1` |

### Benchmark Matrix

| Variable | Description | Default |
|----------|-------------|---------|
| `PROVIDERS` | Comma-separated provider model names. Available: `gpt-4o-openai`, `gpt-4o-azure`, `gpt-4o-bedrock`, `claude-sonnet-anthropic`, `claude-sonnet-vertex` | `gpt-4o-openai,claude-sonnet-anthropic` |
| `PAYLOAD_SIZES` | Comma-separated payload sizes. `small`=32/64 tokens, `medium`=256/512, `large`=1024/1024, `very-large`=2048/2048 | `small,medium` |
| `CONCURRENCY_LEVELS` | Comma-separated concurrent request counts | `8,32,64,128,512` |
| `BENCHMARK_DURATION` | Duration per benchmark run in seconds | `90` |
| `WARMUP` | Warmup seconds (discarded from results) | `30` |

### GuideLLM

| Variable | Description | Default |
|----------|-------------|---------|
| `GUIDELLM_IMAGE` | Container image with GuideLLM + results parser baked in | `ghcr.io/cloud-bulldozer/guidellm-results-parser:v0.0.4` |
| `SAMPLES` | Number of benchmark samples per Job (K8s Job completions) | `3` |
| `PARALLELISM` | K8s Job parallelism for benchmark runs | `1` |
| `PAUSE` | Pause duration after each benchmark before Job pod exits | `10s` |

### kube-burner-ocp

| Variable | Description | Default |
|----------|-------------|---------|
| `KUBE_BURNER_VERSION` | Version to download. Set `default` to use the built-in default | `1.12.0` |
| `KUBE_BURNER_URL` | Direct URL to a kube-burner-ocp binary. Overrides `KUBE_BURNER_VERSION` | (unset) |
| `QPS` | Client-go QPS | `20` |
| `BURST` | Client-go burst | `20` |
| `GC` | Garbage collect created namespaces after benchmark | `true` |
| `LOG_LEVEL` | Log level: `debug`, `info`, `warn`, `error` | `info` |
| `EXTRA_FLAGS` | Additional flags appended to the kube-burner-ocp command | (empty) |

### Indexing

| Variable | Description | Default |
|----------|-------------|---------|
| `ES_SERVER` | OpenSearch/Elasticsearch endpoint URL. Indexing disabled when unset | (unset) |
| `ES_INDEX` | Index name for kube-burner Prometheus metrics | `maas-gateway-perf` |
| `UUID` | Benchmark run identifier | (auto-generated) |

### CI

| Variable | Description | Default |
|----------|-------------|---------|
| `KUBE_DIR` | Directory for downloaded binaries | `/tmp` |
| `ARTIFACT_DIR` | CI artifact directory (set automatically by Prow) | (unset) |

## RHOAI vs ODH

Both operators are installed from scratch by the MaaS `deploy.sh` script. No pre-existing operator is required.

| Aspect | `OPERATOR_TYPE=odh` | `OPERATOR_TYPE=rhoai` |
|--------|--------------------|-----------------------|
| Operator | `opendatahub-operator` from community-operators | `rhods-operator` from redhat-operators |
| App namespace | `opendatahub` | `redhat-ods-applications` |
| Policy engine | Kuadrant (upstream v1.4.2) | RHCL (Red Hat Connectivity Link) |
| Policy engine source | Custom CatalogSource (quay.io/kuadrant) | redhat-operators catalog |

The benchmark results are functionally identical — the gateway data plane (Envoy + Authorino + IPP + Limitador) is the same. The difference is which operator deploys and manages it.

## Test Matrix

The total number of GuideLLM Jobs created is:

```
Jobs = providers x payload_sizes x concurrency_levels x 2 (baseline + gateway) x samples
```

With defaults: `2 x 2 x 5 x 2 x 3 = 120 Job pods` (40 unique A/B pairs, 3 samples each).

### Available Providers

| Provider | `spec.provider` | Translation | Overhead |
|----------|-----------------|-------------|----------|
| `gpt-4o-openai` | `openai` | Passthrough | Minimal |
| `gpt-4o-azure` | `azure-openai` | Path rewrite | Minimal |
| `gpt-4o-bedrock` | `bedrock` | Passthrough | Minimal |
| `claude-sonnet-anthropic` | `anthropic` | Full body translation (OpenAI to Anthropic Messages API) | Higher |
| `claude-sonnet-vertex` | `vertexai` | Full body translation (OpenAI to Vertex AI) | Higher |

### Payload Sizes

| Size | Prompt Tokens | Output Tokens |
|------|--------------|---------------|
| `small` | 32 | 64 |
| `medium` | 256 | 512 |
| `large` | 1024 | 1024 |
| `very-large` | 2048 | 2048 |

## KPIs Captured

| Metric | Source | Description |
|--------|--------|-------------|
| Request latency (mean/p50/p95/p99) | GuideLLM | End-to-end request latency |
| Requests per second | GuideLLM | Throughput under load |
| TTFT (Time to First Token) | GuideLLM | First token latency |
| ITL (Inter-Token Latency) | GuideLLM | Streaming token gap |
| Gateway overhead | Derived (gateway - baseline) | Net latency added by the MaaS stack |
| Istio gateway latency | Prometheus (kube-burner) | Gateway-level request duration histogram |
| Authorino auth duration | Prometheus (kube-burner) | Authentication evaluation time |
| Pod CPU/memory | Prometheus (kube-burner) | Resource consumption of gateway, IPP, simulator pods |
| Limitador counters | Prometheus (kube-burner) | Rate limiting metrics (authorized/limited calls) |

## Using EXTRA_FLAGS

Additional kube-burner-ocp flags can be passed through:

```shell
# Increase timeout for large matrix runs
$ EXTRA_FLAGS="--timeout=8h" ./run.sh

# Disable alerting
$ EXTRA_FLAGS="--alerting=false" ./run.sh

# Use local indexing instead of ES
$ EXTRA_FLAGS="--local-indexing" ./run.sh

# Override the guidellm container image
$ EXTRA_FLAGS="--guidellm-image=my-registry/guidellm:custom" ./run.sh
```
