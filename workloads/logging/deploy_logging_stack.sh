#!/usr/bin/env bash

set -e

# Source env.sh to read all the vars
source env.sh

# Logging format
log() {
  echo ${bold}$(date -u):  ${@}${normal}
}

# Check if oc client is installed
log "Checking if oc client is installed"
which oc &>/dev/null
if [[ $? != 0 ]]; then
  log "Looks like oc client is not installed, please install before continuing"
  log "Exiting"
  exit 1
fi

# Check if cluster exists and print the clusterversion under test
oc get clusterversion
if [[ $? -ne 0 ]]; then
  log "Unable to connect to the cluster, please check if it's up and make sure the KUBECONFIG is set correctly"
  exit 1
fi

function install() {
  # create cluster logging and elasticsearch resources
  log "Creating cluster logging and elastisearch resources"
  envsubst < ./files/logging-stack.yml | oc create -f -
}

wait_time=0
function cleanup() {
  oc delete --wait=true project openshift-logging --ignore-not-found
  oc delete --wait=true project openshift-operators-redhat --ignore-not-found
  while [[ $( oc get projects | grep -w "openshift-logging\|openshift-operators-redhat") ]]; do
    sleep 5
    wait_time=$((wait_time+5))
    if [[ $wait_time -ge $TIMEOUT ]]; then
      log "openshift-logging/openshift-operators-redhat namespaces still exists after $TIMEOUT, please check. Exiting"
      exit 1
    fi
  done
}

# Delete the namespaces if already exists
log "Deteting openshift-logging/openshift-operators-redhat namespaces if exists"
cleanup

# Install the necessary objects for setting up elastic and logging operators and create a cluster logging instance
log "Installing the necessary objects for setting up elastic and logging operators and creating a cluster logging instance"
install

# Wait till the logging stack is up
log "Waiting for the logging stack is up"
log "Sleeping for 60 seconds for the cluster logging operator to initialize and create the logging stack deployments and daemonsets before checking the status"
sleep 60
oc wait --for=condition=available -n openshift-logging deployment/cluster-logging-operator --timeout=180s
log "Checking the status"
for deployment in $( oc get deployments -n openshift-logging | awk 'NR!=1{print $1}'); do oc wait --for=condition=available -n openshift-logging deployment/$deployment --timeout=180s; done
wait_time=0
while [[ $( oc get daemonset.apps/fluentd -n openshift-logging -o=jsonpath='{.status.desiredNumberScheduled}' ) != $( oc get daemonset.apps/fluentd -n openshift-logging -o=jsonpath='{.status.numberReady}' ) ]]; do
  log "Waiting for fluentd daemonset"
  sleep 5
  wait_time=$((wait_time+5))
  if [[ $wait_time -ge $TIMEOUT ]]; then
    log "FLuentd daemonset is not ready after $TIMEOUT, please check. Exiting"
    exit 1
  fi
done
log "Logging stack including Elasticsearch, Fluend and Kibana is up"
