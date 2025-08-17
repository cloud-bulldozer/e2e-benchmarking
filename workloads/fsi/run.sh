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
OC_VERSION=$(oc get clusterversion -o json | jq -r '.items[0].status.desired.version')
WORKER_COUNT=$(oc get no --no-headers -l node-role.kubernetes.io/worker | wc -l)
ES_INDEX="ripsaw-kube-burner-mohit"
EXTRA_FLAGS=${EXTRA_FLAGS:-}

export UUID=${UUID:-$(uuidgen)}

log INFO "🖥️ Cluster version: $OC_VERSION, Worker nodes: $WORKER_COUNT"

clone_or_update_repo() {
    if [ ! -d "$BOA_DIR" ]; then
        log INFO "🏗️ Cloning Bank of Anthos..."
        git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git "$BOA_DIR"
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
  - frontend.yaml
  - ledger-db.yaml
  - ledger-writer.yaml
  - transaction-history.yaml
  - userservice.yaml
EOL
    log INFO "✅ Base kustomization.yaml written. "
}

apply_jwt_secret() {
    if [ -f "$BOA_DIR/extras/jwt/jwt-secret.yaml" ]; then
        log INFO "🔑 Applying JWT secret..."
        kubectl apply -f "$BOA_DIR/extras/jwt/jwt-secret.yaml"
    else
        log WARN "JWT secret file not found at $BOA_DIR/extras/jwt/jwt-secret.yaml. Skipping."
    fi
}

apply_overlay() {
    if [ ! -d "$OVERLAY_DIR" ]; then
        log ERROR "Overlay directory $OVERLAY_DIR does not exist!"
        exit 1
    fi

    log INFO "📝 Generating loadgenerator Job from template..."
    # Substitute environment variables in the template
    envsubst < "$OVERLAY_DIR/loadgenerator-job-template.yaml" > "$OVERLAY_DIR/loadgenerator-job.yaml"

    log INFO "🛠️  Applying overlay with patches..."
    START_TIME=$(date +%s)
    oc apply -k "$OVERLAY_DIR"
}

wait_for_loadgen() {
    # Get the loadgenerator pod name
    LOADGEN_POD=$(oc get pod -l job-name=loadgenerator -o jsonpath='{.items[0].metadata.name}')

    TIMEOUT=600  # 10 minutes
    INTERVAL=5
    ELAPSED=0
    log INFO "⏳ Waiting for loadgenerator pod [$LOADGEN_POD] to finish..."
    oc wait --for=condition=Ready pod -l job-name=loadgenerator
    while true; do
        if oc logs "$LOADGEN_POD" | grep -q "Sleeping"; then
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
    apply_jwt_secret
    apply_overlay
    wait_for_loadgen
    kube_burner_index
    log INFO "===== 🎉 Setup complete. 🎉 ====="
    JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}
    WORKLOAD="fsi"
    env JOB_START="$JOB_START" JOB_END="$JOB_END" UUID="$UUID" WORKLOAD="$WORKLOAD" ES_SERVER="$ES_SERVER" $WRAPPER_DIR/../../utils/index.sh
}

main "$@"

