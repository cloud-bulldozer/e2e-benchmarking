#!/usr/bin/env bash

compare(){
  local benchmark=${1}
  local base_uuid=${2}
  local compare_uuid=${3}
  local output_file=${4}
  python3 -m venv ./venv
  source ./venv/bin/activate
  pip3 install git+https://github.com/cloud-bulldozer/touchstone
  if [[ $? -ne 0 ]] ; then
    echo "Unable to execute compare - Failed to install touchstone"
    exit 1
  fi
  touchstone_compare ${benchmark} elasticsearch ripsaw -url ${ES_SERVER} ${ES_SERVER_BASELINE} -u ${base_uuid} ${compare_uuid} -o yaml | tee ${output_file}
  if [[ $? -ne 0 ]] ; then
    echo "Unable to execute compare - Failed to run touchstone"
    exit 1
  fi
  deactivate
  rm -rf venv
}
