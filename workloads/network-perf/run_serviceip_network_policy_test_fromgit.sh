#!/usr/bin/env bash
export WORKLOAD=service
export NETWORK_POLICY=true

source ./common.sh
export SERVICEIP=true
if [[ "${isBareMetal}" == "true" ]]; then
  export METADATA_TARGETED=true
fi

for pairs in 1 2 4; do
  export pairs=${pairs}
  run_workload ripsaw-uperf-crd.yaml
  if [[ $? != 0 ]]; then
    exit 1
  fi
  assign_uuid
  run_benchmark_comparison
done
generate_csv
log "Finished workload run_serviceip_network_policy_test_fromgit.sh"
