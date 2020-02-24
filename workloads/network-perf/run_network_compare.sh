#!/usr/bin/env bash
datasource="elasticsearch"
tool="uperf"
function="compare"
throughput_tolerance=5
latency_tolerance=5

if [ "$#" -ne 2 ]; then
  echo "Syntax error : Script expects two UUIDs"
  echo "               ./run_network_compare.sh <baseline_uuid> <new_uuid>"
  exit 1
fi

base_uuid=$1
compare_uuid=$2
es_server=${ES_SERVER}
es_port=${ES_PORT}
es_server_baseline=${ES_SERVER}
es_port_baseline=${ES_PORT}

if [ "$es_server" == "" ] || [ "$es_port" == "" ]; then
  echo "Unable to execute compare - no elasticsearch server and/or port passed"
  exit 1
fi

if [[ ${ES_SERVER_BASELINE} ]] && [[ ${ES_PORT_BASELINE} ]]; then
  es_server_baseline=${ES_SERVER_BASELINE}
  es_port_baseline=${ES_PORT_BASELINE}
fi

if [[ ${THROUGHPUT_TOLERANCE} ]]; then
  throughput_tolerance=${THROUGHPUT_TOLERANCE}
fi

if [[ ${LATENCY_TOLERANCE} ]]; then
  latency_tolerance=${LATENCY_TOLERANCE}
fi

git clone https://github.com/cloud-bulldozer/touchstone
cd touchstone
python3 -m venv ./compare
source ./compare/bin/activate
pip3 install -r requirements.txt
python3 setup.py develop
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to install touchstone"
  exit 1
fi

touchstone_compare $tool $datasource ripsaw -url $es_server_baseline:$es_port_baseline $es_server:$es_port -u $base_uuid $compare_uuid -o yaml | tee ../compare.yaml
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to run touchstone"
  exit 1
fi
cd ../
failed=0
echo "Checking Stream TCP"
python3 compare.py --result compare.yaml --uuid $base_uuid --test stream --protocol tcp --tolerance $throughput_tolerance || failed=1
echo "Checking Stream UDP"
python3 compare.py --result compare.yaml --uuid $base_uuid --test stream --protocol udp --tolerance $throughput_tolerance || failed=1
echo "Checking RR TCP"
python3 compare.py --result compare.yaml --uuid $base_uuid --test rr --protocol tcp --tolerance $latency_tolerance || failed=1
echo "Checking RR UDP"
python3 compare.py --result compare.yaml --uuid $base_uuid --test rr --protocol tcp --tolerance $latency_tolerance || failed=1
echo "Compare complete"
exit $failed
