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
  Phase 1: Obtain kube-burner-ocp binary
  Phase 2: Deploy MaaS platform via the upstream deploy scripts
           test/e2e/scripts/deploy-platform.sh -> scripts/deploy.sh
           test/e2e/scripts/deploy-aigc-companion.sh
           Installs: cert-manager, LWS, RHCL, ODH/RHOAI operator,
                     DSC, PostgreSQL, Gateway, MaaS controller, maas-api,
                     ai-gateway-controller + praxis dataplane
  Phase 2b: Create PodMonitor/ServiceMonitors for prometheus-k8s
  Phase 3: Register benchmark models (multi-provider simulator,
           ExternalModels, MaaSModelRefs, HTTPRoutes, AuthPolicy, Subscription)
  Phase 4: Discover gateway and simulator endpoints
  Phase 5: Run kube-burner-ocp maas-gateway-perf
           Jobs 1..N: GuideLLM K8s Jobs — baseline A/B pairs per provider/payload/concurrency
           Jobs N+1..2N: GuideLLM K8s Jobs — gateway A/B pairs
           Last job: Cleanup
  Phase 6: Copy collected metrics to artifact directory
  Phase 7: Index CI metadata via utils/index.sh
```

### Platform parity with MaaS CI

Phase 2 does not reimplement the deployment. It runs the same scripts that
[`test/e2e/scripts/prow_run_smoke_test.sh`](https://github.com/opendatahub-io/models-as-a-service/blob/main/test/e2e/scripts/prow_run_smoke_test.sh)
runs in the MaaS e2e CI job, and those scripts already default to exactly what
that job deploys: kustomize deployment mode, the `rhcl` policy engine,
`ocproute` ingress, and `sslmode=disable` on the POC PostgreSQL. A perf run and
a CI smoke run therefore stand up the same platform, and this workload only
layers the benchmark-specific models on top of it.

Because the defaults live upstream, any variable those scripts read can be
exported before `run.sh` and is passed straight through — `DEPLOY_MODE`,
`POLICY_ENGINE`, `INGRESS_MODE`, `INSECURE_HTTP`, `EXTERNAL_OIDC`,
`OPERATOR_CATALOG`, `OPERATOR_IMAGE`, `OPERATOR_CHANNEL`, `MAAS_API_IMAGE`,
`MAAS_CONTROLLER_IMAGE`, and the rest of `scripts/deploy.sh --help`.

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

Re-benchmark a cluster that already has MaaS on it, skipping the deployment:

```shell
$ SKIP_DEPLOYMENT=true ./run.sh
```

## Environment Variables

### Platform

| Variable | Description | Default |
|----------|-------------|---------|
| `OPERATOR_TYPE` | Operator to deploy: `odh` or `rhoai`. Determines the operator and namespaces | `odh` |
| `MAAS_REF` | Git tag/branch of `opendatahub-io/models-as-a-service` to deploy | `main` |
| `MAAS_REPO` | Clone URL for the MaaS repo | `https://github.com/opendatahub-io/models-as-a-service.git` |
| `SKIP_DEPLOYMENT` | Benchmark a cluster that already has MaaS deployed | `false` |
| `AI_GATEWAY_CONTROLLER_IMAGE` | AIGC companion dataplane image, as CI defaults it. Set to `""` to skip the companion install | `quay.io/opendatahub/odh-ai-gateway-controller:latest` |

Anything else `scripts/deploy.sh` / `deploy-platform.sh` reads is passed
through unchanged — see "Platform parity with MaaS CI" above.

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
| `GUIDELLM_IMAGE` | Container image with GuideLLM + results parser baked in | `ghcr.io/cloud-bulldozer/guidellm-results-parser:v0.0.5` |
| `SAMPLES` | Number of benchmark samples per Job (K8s Job completions) | `3` |
| `PARALLELISM` | K8s Job parallelism for benchmark runs | `1` |
| `PAUSE` | Pause duration after each benchmark before Job pod exits | `10s` |

### kube-burner-ocp

| Variable | Description | Default |
|----------|-------------|---------|
| `KUBE_BURNER_VERSION` | Release version to download. Set `default` to use the built-in default | `1.12.8` |
| `KUBE_BURNER_URL` | Direct URL to a kube-burner-ocp release tarball. Overrides `KUBE_BURNER_VERSION` | (unset) |
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
| Infra namespace | `odh-ai-gateway-infra` | `redhat-ai-gateway-infra` |

Both use the `rhcl` policy engine, because that is what the MaaS CI job pins.
`deploy.sh` on its own would auto-select upstream Kuadrant for ODH; export
`POLICY_ENGINE=kuadrant` to get that instead.

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
