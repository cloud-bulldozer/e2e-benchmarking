#!/bin/bash
set -euo pipefail

# --- Logging function ---
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] $msg"
}

echo "===== 🌟 STARTING BoA WRAPPER SETUP ====="

WRAPPER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BOA_DIR="$WRAPPER_DIR/bank-of-anthos-base"
OVERLAY_DIR="$WRAPPER_DIR/overlay-my-env"

clone_or_update_repo() {
    if [ ! -d "$BOA_DIR" ]; then
        log INFO "Cloning Bank of Anthos..."
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

    log INFO "Writing base kustomization.yaml..."
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
    log INFO "Base kustomization.yaml written. ✅"
}

apply_jwt_secret() {
    if [ -f "$BOA_DIR/extras/jwt/jwt-secret.yaml" ]; then
        log INFO "Applying JWT secret..."
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
    log INFO "Applying overlay with patches..."
    oc apply -k "$OVERLAY_DIR"
}

main() {
    clone_or_update_repo
    apply_jwt_secret
    apply_overlay
    log INFO "===== Setup complete. Overlay applied. 🎉 ====="
}

main "$@"

