#!/bin/bash -e

set -e

source env.sh

OS=$(uname -s)
HARDWARE=$(uname -m)

MAAS_DIR="${MAAS_DIR:-${KUBE_DIR}/models-as-a-service}"

# Namespaces and names, defaulted exactly as the upstream MaaS scripts default
# them. Override any of them in the environment if a deployment moves.
if [[ "${OPERATOR_TYPE}" == "rhoai" ]]; then
  DEPLOYMENT_NAMESPACE="${DEPLOYMENT_NAMESPACE:-redhat-ods-applications}"
  INFRA_NAMESPACE="${INFRA_NAMESPACE:-redhat-ai-gateway-infra}"
else
  DEPLOYMENT_NAMESPACE="${DEPLOYMENT_NAMESPACE:-opendatahub}"
  INFRA_NAMESPACE="${INFRA_NAMESPACE:-odh-ai-gateway-infra}"
fi
MODEL_NAMESPACE="${MODEL_NAMESPACE:-llm}"
MAAS_SUBSCRIPTION_NAMESPACE="${MAAS_SUBSCRIPTION_NAMESPACE:-models-as-a-service}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-openshift-ingress}"
GATEWAY_NAME="${GATEWAY_NAME:-maas-default-gateway}"
AUTHORINO_NAMESPACE="${AUTHORINO_NAMESPACE:-${RHCL_NAMESPACE:-kuadrant-system}}"
export DEPLOYMENT_NAMESPACE MODEL_NAMESPACE MAAS_SUBSCRIPTION_NAMESPACE
export GATEWAY_NAMESPACE GATEWAY_NAME

# ============================================================
# Phase 1: Download kube-burner-ocp
# ============================================================

download_kube_burner() {
  if [[ -z ${KUBE_BURNER_URL} ]]; then
    KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-${OS}-${HARDWARE}.tar.gz"
  fi
  curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
}

install_dependencies() {
  if ! command -v kustomize &>/dev/null || \
     ! kustomize version 2>/dev/null | grep -qE 'v[5-9]\.[7-9]|v[5-9]\.[1-9][0-9]|v[6-9]\.'; then
    echo "Installing kustomize v5.7.0..."
    local kust_os kust_arch
    kust_os=$(uname -s | tr '[:upper:]' '[:lower:]')
    kust_arch=$(uname -m)
    [[ "${kust_arch}" == "x86_64" ]] && kust_arch="amd64"
    [[ "${kust_arch}" == "aarch64" || "${kust_arch}" == "arm64" ]] && kust_arch="arm64"
    curl --fail --retry 3 -sS -L \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.7.0/kustomize_v5.7.0_${kust_os}_${kust_arch}.tar.gz" \
      | tar -xzC "${KUBE_DIR}/"
    export PATH="${KUBE_DIR}:${PATH}"
  fi

  # deploy.sh requires GNU sed as `gsed` on macOS.
  if [[ "${OS}" == "Darwin" ]] && ! command -v gsed &>/dev/null; then
    echo "Installing gsed (GNU sed)..."
    command -v brew &>/dev/null && brew install gnu-sed 2>/dev/null || true
  fi

  if ! command -v envsubst &>/dev/null; then
    echo "Installing envsubst (gettext)..."
    if command -v brew &>/dev/null; then
      brew install gettext 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
      dnf install -y gettext 2>/dev/null || true
    elif command -v apt-get &>/dev/null; then
      apt-get install -y gettext-base 2>/dev/null || true
    fi
  fi
}

echo "Installing dependencies..."
install_dependencies

echo "Downloading kube-burner-ocp v${KUBE_BURNER_VERSION}..."
download_kube_burner

# ============================================================
# Phase 2: Deploy MaaS Platform
# ============================================================
#
# The platform is deployed by the upstream scripts themselves rather than by a
# copy of their logic kept here:
#
#   test/e2e/scripts/deploy-platform.sh  -> scripts/deploy.sh
#   test/e2e/scripts/deploy-aigc-companion.sh
#
# Those are the same scripts test/e2e/scripts/prow_run_smoke_test.sh runs in
# CI, and they carry the same defaults it relies on (kustomize mode, rhcl
# policy engine, ocproute ingress, sslmode=disable). So a perf run and a CI
# smoke run stand up the same platform, and anything the perf benchmark needs
# on top is layered on afterwards in phases 2b and 3.

deploy_maas_platform() {
  echo "Deploying MaaS platform (${MAAS_REF}) with operator type: ${OPERATOR_TYPE}"

  # Re-clone unless a complete checkout is already present. A bare directory
  # check is not enough: /tmp reapers delete the files but leave the tree.
  if [[ ! -x "${MAAS_DIR}/scripts/deploy.sh" ]]; then
    rm -rf "${MAAS_DIR}"
    git clone --branch "${MAAS_REF}" --depth 1 "${MAAS_REPO}" "${MAAS_DIR}"
  fi
  # setup-shared-deps.sh falls back to <repo>/bin for helm when /usr/local/bin
  # is not writable, and does not create that directory itself.
  mkdir -p "${MAAS_DIR}/bin"

  if ! bash "${MAAS_DIR}/test/e2e/scripts/deploy-platform.sh"; then
    echo "ERROR: MaaS deploy-platform.sh failed"
    return 1
  fi

  if [[ -n "${AI_GATEWAY_CONTROLLER_IMAGE}" ]]; then
    echo "Installing the AIGC companion dataplane..."
    if ! bash "${MAAS_DIR}/test/e2e/scripts/deploy-aigc-companion.sh"; then
      echo "ERROR: deploy-aigc-companion.sh failed"
      return 1
    fi
  fi

  # Without this maas-controller only reconciles tenants in its own namespace,
  # so the MaaSModelRefs registered in ${MODEL_NAMESPACE} below never go Ready.
  # Same patch prow_run_smoke_test.sh applies before its tests.
  if oc get deployment maas-controller -n "${DEPLOYMENT_NAMESPACE}" &>/dev/null; then
    if ! oc get deployment maas-controller -n "${DEPLOYMENT_NAMESPACE}" \
         -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null \
         | grep -q 'enable-tenant-namespace-discovery'; then
      echo "Enabling tenant namespace discovery on maas-controller..."
      oc patch deployment maas-controller -n "${DEPLOYMENT_NAMESPACE}" --type=json -p='[
        {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-tenant-namespace-discovery=true"}
      ]' && oc rollout status deployment/maas-controller -n "${DEPLOYMENT_NAMESPACE}" --timeout=180s
    fi
  else
    echo "WARNING: maas-controller not found in ${DEPLOYMENT_NAMESPACE}, skipping tenant namespace discovery"
  fi

  echo "Waiting for maas-api deployment in ${INFRA_NAMESPACE}..."
  oc wait --for=condition=Available --timeout=600s \
    deployment/maas-api -n "${INFRA_NAMESPACE}" || {
      echo "ERROR: maas-api not ready after 600s"
      oc get pods -n "${INFRA_NAMESPACE}" -l app.kubernetes.io/name=maas-api
      return 1
    }

  echo "Waiting for gateway..."
  oc wait --for=condition=Programmed --timeout=600s \
    "gateway/${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" || {
      echo "ERROR: Gateway not ready after 600s"
      oc get gateway -n "${GATEWAY_NAMESPACE}"
      return 1
    }
}

if [[ "${SKIP_DEPLOYMENT}" == "true" ]]; then
  echo "Skipping MaaS platform deployment (SKIP_DEPLOYMENT=true)"
elif ! deploy_maas_platform; then
  echo "ERROR: MaaS platform deployment failed, aborting benchmark"
  exit 1
fi

# ============================================================
# Phase 2b: Create metrics monitors for prometheus-k8s
# ============================================================

setup_metrics_monitoring() {
  echo "Creating metrics monitors..."

  cat <<EOF | oc apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: maas-gateway-istio-metrics
  namespace: ${GATEWAY_NAMESPACE}
spec:
  selector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: ${GATEWAY_NAME}
  podMetricsEndpoints:
  - port: metrics
    path: /stats/prometheus
    interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: authorino-metrics
  namespace: openshift-monitoring
spec:
  namespaceSelector:
    matchNames:
    - ${AUTHORINO_NAMESPACE}
  selector:
    matchLabels:
      authorino-resource: authorino
      control-plane: controller-manager
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: limitador-metrics
  namespace: openshift-monitoring
spec:
  namespaceSelector:
    matchNames:
    - ${AUTHORINO_NAMESPACE}
  selector:
    matchLabels:
      app: limitador
      limitador-resource: limitador
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
EOF

  echo "Metrics monitoring setup complete"
}

setup_metrics_monitoring

# ============================================================
# Phase 3: Register models for gateway benchmarks
# ============================================================
#
# CI applies test/e2e/fixtures, whose LLMInferenceServices exist to satisfy
# its assertions. The benchmark instead needs one simulator serving every
# provider in ${PROVIDERS} with fixed token timings and rate limits high
# enough not to shape the load, so it registers its own models on top of the
# platform CI deployed.

register_test_models() {
  echo "Registering test models for gateway benchmarks..."
  local MODEL_NS="${MODEL_NAMESPACE}"
  local TENANT_NS="${MAAS_SUBSCRIPTION_NAMESPACE}"

  oc create ns "${MODEL_NS}" 2>/dev/null || true
  oc create ns "${TENANT_NS}" 2>/dev/null || true

  # Deploy simulator in model namespace
  cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-d-inference-sim
  namespace: ${MODEL_NS}
  labels:
    app: llm-d-inference-sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-d-inference-sim
  template:
    metadata:
      labels:
        app: llm-d-inference-sim
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: simulator
        image: quay.io/rh-ee-aharush/llm-d-inference-sim:multi-provider
        imagePullPolicy: Always
        args:
        - "--model"
        - "gpt-4o-openai"
        - "--served-model-name"
        - "gpt-4o-openai"
        - "gpt-4o-azure"
        - "gpt-4o-bedrock"
        - "claude-sonnet-anthropic"
        - "claude-sonnet-vertex"
        - "--port"
        - "8000"
        - "--mode"
        - "random"
        - "--providers"
        - "anthropic,azure,bedrock,vertexai"
        - "--max-model-len"
        - "8192"
        - "--max-num-seqs"
        - "1000"
        - "--time-to-first-token"
        - "1"
        - "--inter-token-latency"
        - "1"
        - "--deterministic-tokens"
        ports:
        - containerPort: 8000
          name: http
          protocol: TCP
        resources:
          requests:
            cpu: "500m"
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: llm-d-inference-sim
  namespace: ${MODEL_NS}
spec:
  type: ClusterIP
  selector:
    app: llm-d-inference-sim
  ports:
  - port: 8000
    targetPort: 8000
    protocol: TCP
    name: http
EOF

  echo "Waiting for simulator to be ready..."
  oc wait --for=condition=Available --timeout=120s deployment/llm-d-inference-sim -n "${MODEL_NS}" || {
    echo "ERROR: Simulator not ready"
    return 1
  }

  local PROVIDERS_LIST
  IFS=',' read -ra PROVIDERS_LIST <<< "${PROVIDERS}"

  # Create ExternalModel + MaaSModelRef + Secret + HTTPRoute per provider
  for provider in "${PROVIDERS_LIST[@]}"; do
    # maas.opendatahub.io/ExternalModel is rejected by the vexternalmodel
    # webhook as of MaaS 3.6. The replacement splits that single object into an
    # inference.opendatahub.io ExternalProvider (where the backend lives) and an
    # ExternalModel (how a model binds to it). Provider ids were renamed too.
    local provider_type="openai"
    case "$provider" in
      *azure*)     provider_type="azure" ;;
      *bedrock*)   provider_type="aws-bedrock" ;;
      *anthropic*) provider_type="anthropic" ;;
      *vertex*)    provider_type="vertex" ;;
    esac

    # apiFormat drives request/response translation, which is exactly the
    # overhead the gateway half of the A/B is there to measure.
    local api_format="openai-chat" api_path="/v1/chat/completions"
    if [[ "${provider_type}" == "anthropic" ]]; then
      api_format="messages"
      api_path="/v1/messages"
    fi

    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${provider}-creds
  namespace: ${MODEL_NS}
  labels:
    inference.networking.k8s.io/bbr-managed: "true"
    inference.llm-d.ai/ipp-managed: "true"
type: Opaque
stringData:
  api-key: "dummy-perf-test-key"
---
apiVersion: inference.opendatahub.io/v1alpha1
kind: ExternalProvider
metadata:
  name: ${provider}
  namespace: ${MODEL_NS}
  annotations:
    maas.opendatahub.io/tls: "false"
    maas.opendatahub.io/port: "8000"
spec:
  provider: ${provider_type}
  endpoint: llm-d-inference-sim.${MODEL_NS}.svc.cluster.local
  auth:
    type: apikey
    secretRef:
      name: ${provider}-creds
---
apiVersion: inference.opendatahub.io/v1alpha1
kind: ExternalModel
metadata:
  name: ${provider}
  namespace: ${MODEL_NS}
spec:
  externalProviderRefs:
  - ref:
      name: ${provider}
      namespace: ${MODEL_NS}
    apiFormat: ${api_format}
    path: ${api_path}
    targetModel: ${provider}
---
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: ${provider}
  namespace: ${MODEL_NS}
spec:
  modelRef:
    kind: ExternalModel
    name: ${provider}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: perf-${provider}
  namespace: ${MODEL_NS}
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: ${GATEWAY_NAME}
    namespace: ${GATEWAY_NAMESPACE}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /${provider}/
    backendRefs:
    - name: llm-d-inference-sim
      port: 8000
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
  - matches:
    - headers:
      - name: X-Gateway-Model-Name
        type: Exact
        value: ${provider}
      path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: llm-d-inference-sim
      port: 8000
EOF
  done

  # MaaSAuthPolicy for all models
  local AUTH_REFS=""
  for provider in "${PROVIDERS_LIST[@]}"; do
    AUTH_REFS+="  - name: ${provider}"$'\n'"    namespace: ${MODEL_NS}"$'\n'
  done

  cat <<EOF | oc apply -f -
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: perf-access
  namespace: ${TENANT_NS}
spec:
  modelRefs:
${AUTH_REFS}  subjects:
    groups:
    - name: "system:authenticated"
EOF

  # MaaSSubscription with high rate limits
  local SUB_REFS=""
  for provider in "${PROVIDERS_LIST[@]}"; do
    SUB_REFS+="  - name: ${provider}"$'\n'"    namespace: ${MODEL_NS}"$'\n'"    tokenRateLimits:"$'\n'"    - limit: 1000000000"$'\n'"      window: 1m"$'\n'
  done

  cat <<EOF | oc apply -f -
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: perf-benchmark
  namespace: ${TENANT_NS}
spec:
  owner:
    groups:
    - name: "system:authenticated"
  modelRefs:
${SUB_REFS}
EOF

  # Wait for reconciliation
  echo "Waiting for model registration to reconcile..."
  sleep 20

  # Patch the broken ExternalName routing created by the reconciler
  for provider in "${PROVIDERS_LIST[@]}"; do
    oc annotate externalmodel.inference.opendatahub.io "${provider}" -n "${MODEL_NS}" \
      opendatahub.io/managed=false --overwrite 2>/dev/null || true

    for route in "${provider}" "maas-${provider}"; do
      if oc get httproute "${route}" -n "${MODEL_NS}" &>/dev/null; then
        oc get httproute "${route}" -n "${MODEL_NS}" -o json | \
          jq '.spec.rules[].backendRefs = [{"name":"llm-d-inference-sim","port":8000,"kind":"Service","group":""}]' | \
          oc replace -f - 2>/dev/null || true
      fi
    done

    if oc get destinationrule "${provider}" -n "${MODEL_NS}" &>/dev/null; then
      oc patch destinationrule "${provider}" -n "${MODEL_NS}" --type=merge \
        -p '{"spec":{"trafficPolicy":{"tls":{"mode":"DISABLE"}}}}' 2>/dev/null || true
    fi
  done

  echo "Model registration complete"
}

register_test_models

# ============================================================
# Phase 4: Determine endpoints
# ============================================================
#
# Resolved the way prow_run_smoke_test.sh resolves its HOST. In the default
# ocproute mode the Gateway runs on the openshift-default GatewayClass with no
# listener hostname and no status address, and is reached through an OpenShift
# Route at maas.<cluster-domain>; reading listeners[0].hostname alone yields an
# empty host there.

GATEWAY_CLASS=$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null || echo "")
GATEWAY_LISTENER_HOST=$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null | awk '{print $1}')

HOST=""
if [[ -n "${MAAS_GATEWAY_HOST:-}" ]]; then
  HOST="${MAAS_GATEWAY_HOST#*://}"
elif [[ -n "${GATEWAY_LISTENER_HOST}" ]]; then
  HOST="${GATEWAY_LISTENER_HOST}"
elif [[ "${GATEWAY_CLASS}" != "openshift-default" ]]; then
  GATEWAY_ADDRESS=$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
  HOST="${GATEWAY_ADDRESS#*://}"
fi
if [[ -z "${HOST}" ]]; then
  CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
  [[ -n "${CLUSTER_DOMAIN}" ]] || { echo "ERROR: could not determine the gateway host"; exit 1; }
  HOST="maas.${CLUSTER_DOMAIN}"
fi

if [[ "${INSECURE_HTTP:-false}" == "true" ]]; then
  GATEWAY_HOST="http://${HOST}"
else
  GATEWAY_HOST="https://${HOST}"
fi

# Pinned into the load pods' hostAliases, which bypasses the ingress router.
# Export GATEWAY_IP="" to resolve ${HOST} normally and measure the edge too.
if [[ -z "${GATEWAY_IP+x}" ]]; then
  GATEWAY_IP=$(oc get svc -n "${GATEWAY_NAMESPACE}" \
    -l "gateway.networking.k8s.io/gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null)
fi
SIMULATOR_HOST="${SIMULATOR_HOST:-http://llm-d-inference-sim.${MODEL_NAMESPACE}.svc.cluster.local:8000}"

echo "Gateway: ${GATEWAY_HOST}"
echo "Gateway IP: ${GATEWAY_IP:-<unset, resolved via DNS>}"
echo "Simulator: ${SIMULATOR_HOST}"

# ============================================================
# Phase 5: Run kube-burner-ocp benchmark
# ============================================================

cmd="${KUBE_DIR}/kube-burner-ocp maas-gateway-perf"
cmd+=" --log-level=${LOG_LEVEL}"
cmd+=" --qps=${QPS} --burst=${BURST} --gc=${GC}"
cmd+=" --uuid ${UUID}"
cmd+=" --gateway-host=${GATEWAY_HOST}"
cmd+=" --gateway-ip=${GATEWAY_IP}"
cmd+=" --simulator-host=${SIMULATOR_HOST}"
cmd+=" --providers=${PROVIDERS}"
cmd+=" --payload-sizes=${PAYLOAD_SIZES}"
cmd+=" --concurrency-levels=${CONCURRENCY_LEVELS}"
cmd+=" --benchmark-duration=${BENCHMARK_DURATION}"
cmd+=" --warmup=${WARMUP}"
cmd+=" --guidellm-image=${GUIDELLM_IMAGE}"
cmd+=" --samples=${SAMPLES}"
cmd+=" --parallelism=${PARALLELISM}"
cmd+=" --pause=${PAUSE}"
cmd+=" ${EXTRA_FLAGS}"

if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --es-server=${ES_SERVER} --es-index=${ES_INDEX}"
fi

echo "$UUID" >> /tmp/"${WORKLOAD}"-uuid.txt

set +e

redacted_cmd=${cmd}
if [[ -n ${ES_SERVER} ]]; then
  redacted_cmd=${redacted_cmd//"${ES_SERVER}"/<redacted-es-server>}
fi
echo "${redacted_cmd}"

JOB_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
$cmd
exit_code=$?
JOB_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ $exit_code -eq 0 ]; then
  JOB_STATUS="success"
else
  JOB_STATUS="failure"
fi

# ============================================================
# Phase 6: Collect artifacts
# ============================================================

if [[ -n ${ARTIFACT_DIR} ]]; then
  echo "Copying results to artifact directory..."
  METRICS_FOLDER="collected-metrics-${UUID}"
  if [[ -d "${METRICS_FOLDER}" ]]; then
    cp -r "${METRICS_FOLDER}" "${ARTIFACT_DIR}/" 2>/dev/null || true
  fi
fi

# ============================================================
# Phase 7: Index CI metadata
# ============================================================

env JOB_START="$JOB_START" JOB_END="$JOB_END" JOB_STATUS="$JOB_STATUS" \
  UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" \
  ../../utils/index.sh

exit $exit_code
