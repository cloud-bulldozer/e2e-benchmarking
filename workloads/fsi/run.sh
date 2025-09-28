#!/bin/bash
set -euo pipefail

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] [${FUNCNAME[1]}] $msg"
}

log INFO "===== 🌟 STARTING BoA WRAPPER SETUP 🌟 ====="

JOB_START=${JOB_START:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}
WRAPPER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BOA_DIR="$WRAPPER_DIR/bank-of-anthos-base"
OVERLAY_DIR="$WRAPPER_DIR/overlay-my-env"
KUBE_DIR=${KUBE_DIR:-/tmp}
OCP_VERSION=$(oc get clusterversion -o json | jq -r '.items[0].status.desired.version')
WORKER_COUNT=$(oc get no --no-headers -l node-role.kubernetes.io/worker | wc -l)
ES_INDEX="kube-burner-fsi"
EXTRA_FLAGS=${EXTRA_FLAGS:-}
NAMESPACE=${NAMESPACE:-fsi-workload}

export UUID=${UUID:-$(uuidgen)}

log INFO "🖥️ Cluster version: $OCP_VERSION, Worker nodes: $WORKER_COUNT"


download_binary(){
  KUBE_BURNER_VERSION=1.7.7
  KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz"
  curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
}

clone_or_update_repo() {
    if [ ! -d "$BOA_DIR" ]; then
        log INFO "🏗️ Cloning Bank of Anthos..."
        git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git "$BOA_DIR" --depth=1
    else
        log INFO "Updating base repo..."
        cd "$BOA_DIR"
        git fetch origin
        git reset --hard origin/main
    fi

    if [ ! -d "$BOA_DIR/kubernetes-manifests" ]; then
        log ERROR "Expected directory $BOA_DIR/kubernetes-manifests not found!"
        exit 1
    fi

    log INFO "📝 Writing base kustomization.yaml..."
    cat > "$BOA_DIR/kubernetes-manifests/kustomization.yaml" <<EOL
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - accounts-db.yaml
  - balance-reader.yaml
  - contacts.yaml
  - config.yaml
  - frontend.yaml
  - ledger-db.yaml
  - ledger-writer.yaml
  - transaction-history.yaml
  - userservice.yaml
EOL
    log INFO "✅ Base kustomization.yaml written. "
}

ensure_namespace() {
    if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log INFO "📦 Creating namespace $NAMESPACE..."
        oc create namespace "$NAMESPACE"
    else
        log INFO "📦 Namespace $NAMESPACE already exists."
    fi
}

grant_permissions() {
    log INFO "🔐 Granting cluster-admin to service accounts in $NAMESPACE..."
    oc adm policy add-scc-to-user anyuid -z bank-of-anthos -n "$NAMESPACE"
    oc adm policy add-cluster-role-to-user cluster-admin -z bank-of-anthos -n "$NAMESPACE"
    oc adm policy add-scc-to-user privileged -z bank-of-anthos -n "$NAMESPACE"
    oc adm policy add-scc-to-user privileged -z default -n "$NAMESPACE"
}

apply_secret() {
    if [ -f "$BOA_DIR/extras/jwt/jwt-secret.yaml" ]; then
        log INFO "🔑 Applying secret..."
        kubectl apply -n "$NAMESPACE" -f "$BOA_DIR/extras/jwt/jwt-secret.yaml"
    else
        log WARN "JWT secret file not found at $BOA_DIR/extras/jwt/jwt-secret.yaml. Skipping."
    fi
}

wait_for_externalip() {
    local FRONTEND_ADDR=""
    while [ -z "$FRONTEND_ADDR" ]; do
        FRONTEND_ADDR=$(oc get svc frontend -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ -z "$FRONTEND_ADDR" ]; then
            echo "Waiting for frontend external IP/hostname..." >&2
            sleep 5
        fi
    done

    echo "$FRONTEND_ADDR"
}

apply_overlay() {
    if [ ! -d "$OVERLAY_DIR" ]; then
        log ERROR "Overlay directory $OVERLAY_DIR does not exist!"
        exit 1
    fi

    # Step 1: Apply base overlay (patches + base manifests)
    log INFO "🛠️ Applying base overlay (excluding loadgenerator job)..."
    START_TIME=$(date +%s)
    oc apply -k "$OVERLAY_DIR" -n "$NAMESPACE"

    # Step 2: Wait for frontend hostname
    log INFO "⏳ Waiting for frontend service external hostname..."
    FRONTEND_ADDR=$(wait_for_externalip)
    log INFO "✅ Frontend external hostname: $FRONTEND_ADDR"

    # Step 3: Generate loadgenerator job from template
    LOADGEN_TEMPLATE="$OVERLAY_DIR/loadgenerator-template/loadgenerator-job-template.yaml"
    LOADGEN_YAML="$OVERLAY_DIR/loadgenerator-template/loadgenerator-job.yaml"

    log INFO "📝 Generating loadgenerator job with FRONTEND_ADDR=$FRONTEND_ADDR..."
    FRONTEND_ADDR="$FRONTEND_ADDR" ES_SERVER="${ES_SERVER:-}" UUID="$UUID" WORKER_COUNT="$WORKER_COUNT" OCP_VERSION="$OCP_VERSION" envsubst < "$LOADGEN_TEMPLATE" > "$LOADGEN_YAML"

    # Step 4: Apply the generated loadgenerator job
    log INFO "🚀 Applying loadgenerator job..."
    oc apply -f "$LOADGEN_YAML" -n "$NAMESPACE"

    END_TIME=$(date +%s)
    log INFO "✅ Overlay applied successfully in $((END_TIME - START_TIME)) seconds."
}

wait_for_loadgen() {
    # Get the loadgenerator pod name
    LOADGEN_POD=$(oc get pod -n "$NAMESPACE" -l job-name=loadgenerator -o jsonpath='{.items[0].metadata.name}')

    TIMEOUT=600  # 10 minutes
    INTERVAL=5
    ELAPSED=0
    log INFO "⏳ Waiting for loadgenerator pod [$LOADGEN_POD] to finish..."
    oc wait -n "$NAMESPACE" --for=jsonpath='{.status.phase}'=Running pod -l job-name=loadgenerator --timeout=${TIMEOUT}s
    while true; do
        if oc logs -n "$NAMESPACE" "$LOADGEN_POD" | grep -q "Sleeping"; then
            log INFO "🏁 Loadgenerator finished workload!"
            break
        fi

        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))

        if [ $ELAPSED -ge $TIMEOUT ]; then
            log ERROR "i❌ ERROR: Timeout waiting for loadgenerator pod [$LOADGEN_POD] to reach 'Sleeping'"
            exit 1
        fi
    done
}

kube_burner_index() {
    cd "$WRAPPER_DIR"
    END_TIME=$(date +%s)
    cmd=("${KUBE_DIR}/kube-burner-ocp" index \
         --start="$START_TIME" \
         --end="$END_TIME" \
         --uuid="$UUID" \
         --es-server="$ES_SERVER" \
         --es-index="$ES_INDEX")

    # If EXTRA_FLAGS is non-empty, split it into words and append to array
    if [ -n "$EXTRA_FLAGS" ]; then
        read -r -a extra <<< "$EXTRA_FLAGS"
        cmd+=("${extra[@]}")
    fi

    echo "Running command: ${cmd[*]}"
    PPROF=false # pprof is not needed for index job
    "${cmd[@]}"
}

main() 
    {
    clone_or_update_repo
    ensure_namespace
    grant_permissions
    apply_secret
    apply_overlay
    wait_for_loadgen
    download_binary
    kube_burner_index
    log INFO "===== 🎉 Setup complete. 🎉 ====="
    JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}
    WORKLOAD="fsi"
    env JOB_START="$JOB_START" JOB_END="$JOB_END" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" $WRAPPER_DIR/../../utils/index.sh
}

main "$@"

