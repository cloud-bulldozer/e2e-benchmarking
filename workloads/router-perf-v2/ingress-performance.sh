#!/usr/bin/env bash

. common.sh

deploy_infra
tune_liveness_probe
deploy_client
for N_CLIENTS in ${CLIENTS}; do
  for N_KEEPALIVE_REQUESTS in ${KEEPALIVE_REQUESTS}; do
    run_mb
  done
done
enable_ingress_opreator
