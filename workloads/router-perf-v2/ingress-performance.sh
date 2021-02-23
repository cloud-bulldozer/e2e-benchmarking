#!/usr/bin/env bash

. common.sh

deploy_infra
tune_liveness_probe
for clients in ${CLIENTS}; do
  for keepalive_requests in ${KEEPALIVE_REQUESTS}; do
    run_mb
  done
done
enable_ingress_operator
cleanup_infra
