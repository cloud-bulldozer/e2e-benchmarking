#!/usr/bin/env bash
datasource="elasticsearch"
tool="mb"
_es=${ES_SERVER:-http://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com:80}
_es_baseline=${ES_SERVER_BASELINE:-http://search-cloud-perf-lqrf3jjtaqo7727m7ynd2xyt4y.us-west-2.es.amazonaws.com:80}

if [[ ${COMPARE} != "true" ]]; then
  compare_uuid=$1
else
  base_uuid=$1
  compare_uuid=$2
fi

python3 -m venv ./venv
source ./venv/bin/activate
pip3 install git+https://github.com/cloud-bulldozer/touchstone

if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to install touchstone"
  exit 1
fi

set -x
if [[ ${!#} == "mb" ]]; then
  touchstone_compare mb elasticsearch ripsaw -url $_es $_es_baseline -u $compare_uuid $base_uuid -o yaml | tee compare.yaml
else
  touchstone_compare uperf elasticsearch ripsaw -url $_es $_es_baseline -u $compare_uuid $base_uuid -o yaml | tee compare_output_${!#}p.yaml
fi
set +x

if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to run touchstone"
  exit 1
fi

deactivate
rm -rf venv
