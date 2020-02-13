#!/usr/bin/env bash
datasource="elasticsearch"
tool="uperf"
function="compare"
if [ "$#" -ne 2 ]; then
  echo "Syntax error : Script expects two UUIDs"
  echo "               ./run_network_compare.sh <baseline_uuid> <new_uuid>"
  exit 1
fi
base_uuid=$1
compare_uuid=$2
es=${ES_SERVER}
if [ "$es" == "" ]; then
  echo "Unable to execute compare - no ES passed"
  exit 1
fi

git clone https://github.com/cloud-bulldozer/touchstone
cd touchstone
python -m venv ./compare
source ./compare/bin/activate
pip install -r requirements.txt
python3 setup.py develop
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to install touchstone"
  exit 1
fi

touchstone_compare $tool $datasource ripsaw -url $es -u $base_uuid $compare_uuid -o yaml | tee ../compare.yaml
if [[ $? -ne 0 ]] ; then
  echo "Unable to execute compare - Failed to run touchstone"
  exit 1
fi

failed=0
cd ../
echo "Checking Stream TCP"
python compare.py --result compare.yaml --uuid $base_uuid --test stream --protocol tcp || failed=1
echo "Checking Stream UDP"
python compare.py --result compare.yaml --uuid $base_uuid --test stream --protocol udp || failed=1
echo "Checking RR TCP"
python compare.py --result compare.yaml --uuid $base_uuid --test rr --protocol tcp || failed=1
echo "Checking RR UDP"
python compare.py --result compare.yaml --uuid $base_uuid --test rr --protocol tcp || failed=1
echo "Compare complete"
exit $failed
