#!/usr/bin/env bash
set -x

# Check cluster's health
if [[ ${CERBERUS_URL} ]]; then
  response=$(curl ${CERBERUS_URL})
  if [ "$response" != "True" ]; then
    echo "Cerberus status is False, Cluster is unhealthy"
    exit 1
  fi
fi

date
oc get clusterversion
if [ $? -ne 0 ]; then
  echo "Workload Failed for $HTTP_TEST_SUFFIX , Unable to connect to the cluster"
  exit 1
fi

if [[ ${COMPARE} == "true" ]]; then
  echo $BASELINE_CLOUD_NAME,$HTTP_TEST_SUFFIX > uuid.txt
else
  echo $HTTP_TEST_SUFFIX > uuid.txt
fi


echo "Starting test for: $HTTP_TEST_SUFFIX"
#git clone http://github.com/openshift-scale/workloads /tmp/workloads
git clone -b change_index http://github.com/mohit-sheth/workloads /tmp/workloads
echo "[orchestration]" > /tmp/workloads/inventory; echo "${ORCHESTRATION_HOST:-localhost}" >> /tmp/workloads/inventory
time ansible-playbook -vv -i /tmp/workloads/inventory /tmp/workloads/workloads/http.yml
oc logs --timestamps -n scale-ci-tooling -f job/scale-ci-http
oc get job -n scale-ci-tooling scale-ci-http -o json | jq -e '.status.succeeded==1'
￼
router_state=1
oc describe job scale-ci-http | grep "1 Succeeded"
if [ $? -eq 0 ]; then
        echo "Router Workload done"
        router_state=$?
fi
if [ "$router_state" == "1" ] ; then
  echo "Workload failed"
  exit 1
fi

compare_router_uuid=$(oc logs $(oc get pods | grep "scale-ci-http" |awk '{print $1}') | grep UUID | awk '{print $3}')
baseline_router_uuid=${BASELINE_ROUTER_UUID}

if [[ ${COMPARE} == "true" ]]; then
  echo ${baseline_router_uuid},${compare_router_uuid} >> uuid.txt
else
  echo ${compare_router_uuid} >> uuid.txt
fi

./run_router_compare.sh ${baseline_router_uuid} ${compare_router_uuid}

python3 csv_gen.py --files compare.yaml
