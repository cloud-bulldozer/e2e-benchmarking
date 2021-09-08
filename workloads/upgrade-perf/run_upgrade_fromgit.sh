#!/usr/bin/env bash
set -x

source ./common.sh

# set the channel to find the builds to upgrade to
if [[ -n $CHANNEL ]]; then
  echo "Setting the upgrade channel to $CHANNEL"
  if [[ "$CHANNEL" == "nightlies" ]]; then
    oc patch clusterversion version --type json -p '[{"op": "add", "path": "/spec/upstream", "value": "https://amd64.ocp.releases.ci.openshift.org/graph"}, {"op": "add", "path": "/spec/channel", "value": "nightly"}]'
  else
    oc patch clusterversion version -p '{"spec":{"channel":"'$CHANNEL'"}}' --type=merge
  fi
else
  echo "Using the default upgrade channel set on the cluster for the upgrades"
fi

if [[ -n $TOIMAGE ]]; then
  run_snafu --tool upgrade -u ${_uuid} --toimage ${TOIMAGE} --timeout ${_timeout} --poll_interval ${_poll_interval}
elif [[ -n $LATEST ]]; then
  run_snafu --tool upgrade -u ${_uuid} --latest ${LATEST} --timeout ${_timeout} --poll_interval ${_poll_interval}
elif [[ -n $TOVERSION ]]; then
  run_snafu --tool upgrade -u ${_uuid} --version ${TOVERSION} --timeout ${_timeout} --poll_interval ${_poll_interval}
fi

_snafu_rc=$?
_current_version=`oc get clusterversions.config.openshift.io | grep version | awk '{print $2}'`

if [[ $_snafu_rc -ne 0 ]]; then
  echo "run_snafu upgrade command failed"
  _rc=1
else
  echo "run_snafu upgrade command completed successfully"
  _rc=0
fi

echo "UUID: $_uuid"
echo "Current version: $_current_version"

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    deactivate
    rm -rf upgrade
    rm -rf /tmp/snafu
    exit 1
  fi
fi

# Cleanup
deactivate
rm -rf upgrade
rm -rf /tmp/snafu
exit $rc
