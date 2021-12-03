#!/usr/bin/env bash

source ./common.sh
export WORKLOAD=${WORKLOAD}

if [[ $WORKLOAD == "hostnet" ]]; then
    export HOSTNETWORK=true
elif [[ $WORKLOAD == "service" ]]; then
    export SERVICEIP=true 
fi

export pairs=${PAIRS:-1}
export UUID=${UUID:-$(uuidgen)}

run_workload ripsaw-uperf-crd.yaml
if [[ $? != 0 ]]; then
  exit 1
fi

log "Finished workload ${0}"
