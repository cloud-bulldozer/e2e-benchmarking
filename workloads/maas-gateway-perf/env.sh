#!/bin/bash
# MaaS Gateway Performance Benchmark - Environment Defaults

export OPERATOR_TYPE=${OPERATOR_TYPE:-odh}
export MAAS_REF=${MAAS_REF:-v0.2.1}
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
export KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.12.6}
export GUIDELLM_IMAGE=${GUIDELLM_IMAGE:-"ghcr.io/cloud-bulldozer/guidellm-results-parser:v0.0.4"}
export PROVIDERS=${PROVIDERS:-"gpt-4o-openai,claude-sonnet-anthropic"}
export PAYLOAD_SIZES=${PAYLOAD_SIZES:-"small,medium"}
export CONCURRENCY_LEVELS=${CONCURRENCY_LEVELS:-"8,32,64,128,512"}
export BENCHMARK_DURATION=${BENCHMARK_DURATION:-90s}
export WARMUP=${WARMUP:-30s}
export SAMPLES=${SAMPLES:-3}
export PARALLELISM=${PARALLELISM:-1}
export PAUSE=${PAUSE:-10s}
export ES_INDEX=${ES_INDEX:-maas-gateway-perf}
export WORKLOAD=${WORKLOAD:-maas-gateway-perf}
export LOG_LEVEL=${LOG_LEVEL:-info}
export QPS=${QPS:-20}
export BURST=${BURST:-20}
export GC=${GC:-true}
export UUID=${UUID:-$(uuidgen)}
export KUBE_DIR=${KUBE_DIR:-/tmp}
export EXTRA_FLAGS=${EXTRA_FLAGS:-}
export OPERATOR_CHANNEL=${OPERATOR_CHANNEL:-}
