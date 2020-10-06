#!/usr/bin/env bash
set -x

source ./common.sh

if [[ -n $TOIMAGE ]]; then
  run_snafu --tool upgrade -u ${_uuid} --version ${_version} --toimage ${TOIMAGE} --timeout ${_timeout} --poll_interval ${_poll_interval}
else
  run_snafu --tool upgrade -u ${_uuid} --version ${_version} --timeout ${_timeout} --poll_interval ${_poll_interval}
fi

_snafu_rc=$?
_current_version=`oc get clusterversions.config.openshift.io | grep version | awk '{print $2}'`

if [[ $_snafu_rc -ne 0 ]]; then
  echo "run_snafu upgrade command failed"
  _rc=1
elif [[ $_current_version != $_version ]]; then
  echo "run_snafu command upgrade completed but not at target version"
  _rc=1
else
  echo "run_snafu upgrade command completed successfully"
  _rc=0
fi

echo "UUID: $_uuid"
echo "Target version: $_version"
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
