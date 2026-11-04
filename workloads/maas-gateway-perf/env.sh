#!/bin/bash
# MaaS Gateway Performance Benchmark - Environment Defaults

# ------------------------------------------------------------------
# MaaS platform
# ------------------------------------------------------------------
# The platform is deployed by the upstream scripts themselves
# (test/e2e/scripts/deploy-platform.sh -> scripts/deploy.sh), which already
# default to what test/e2e/scripts/prow_run_smoke_test.sh deploys in CI:
# ODH, kustomize mode, rhcl policy engine, ocproute ingress, sslmode=disable.
# Only what differs from those defaults is set here. To tweak the deployment,
# export any variable the upstream scripts read -- OPERATOR_TYPE, DEPLOY_MODE,
# POLICY_ENGINE, INGRESS_MODE, INSECURE_HTTP, EXTERNAL_OIDC, OPERATOR_CATALOG,
# MAAS_API_IMAGE, MAAS_CONTROLLER_IMAGE, ... (see scripts/deploy.sh --help) --
# and it is passed straight through.
export MAAS_REPO=${MAAS_REPO:-https://github.com/opendatahub-io/models-as-a-service.git}
export MAAS_REF=${MAAS_REF:-main}
export OPERATOR_TYPE=${OPERATOR_TYPE:-odh}
# Benchmark a cluster that already has MaaS on it.
export SKIP_DEPLOYMENT=${SKIP_DEPLOYMENT:-false}
# OLM never retries a failed bundle unpack unless asked; CI opts in, so do we.
export OLM_BUNDLE_UNPACK_RETRY=${OLM_BUNDLE_UNPACK_RETRY:-true}
# CI installs the companion ai-gateway-controller + praxis dataplane by
# default. Set to "" to skip it.
if [[ -z "${AI_GATEWAY_CONTROLLER_IMAGE+x}" ]]; then
  export AI_GATEWAY_CONTROLLER_IMAGE="quay.io/opendatahub/odh-ai-gateway-controller:latest"
fi

# ------------------------------------------------------------------
# kube-burner-ocp binary (downloaded from the GitHub release)
# ------------------------------------------------------------------
if [ "$KUBE_BURNER_VERSION" = "default" ]; then
    unset KUBE_BURNER_VERSION
fi
export KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-1.12.8}
export KUBE_BURNER_URL=${KUBE_BURNER_URL:-}

# ------------------------------------------------------------------
# Benchmark matrix
# ------------------------------------------------------------------
export GUIDELLM_IMAGE=${GUIDELLM_IMAGE:-"ghcr.io/cloud-bulldozer/guidellm-results-parser:v0.0.5"}
export PROVIDERS=${PROVIDERS:-"gpt-4o-openai,claude-sonnet-anthropic"}
export PAYLOAD_SIZES=${PAYLOAD_SIZES:-"small,medium"}
export CONCURRENCY_LEVELS=${CONCURRENCY_LEVELS:-"8,32,64,128,512"}
export BENCHMARK_DURATION=${BENCHMARK_DURATION:-90s}
export WARMUP=${WARMUP:-30s}
export SAMPLES=${SAMPLES:-3}
export PARALLELISM=${PARALLELISM:-1}
export PAUSE=${PAUSE:-10s}
export EXTRA_FLAGS=${EXTRA_FLAGS:-}

# ------------------------------------------------------------------
# Run metadata
# ------------------------------------------------------------------
export ES_INDEX=${ES_INDEX:-maas-gateway-perf}
export WORKLOAD=${WORKLOAD:-maas-gateway-perf}
export LOG_LEVEL=${LOG_LEVEL:-info}
export QPS=${QPS:-20}
export BURST=${BURST:-20}
export GC=${GC:-true}
export UUID=${UUID:-$(uuidgen)}
export KUBE_DIR=${KUBE_DIR:-/tmp}
