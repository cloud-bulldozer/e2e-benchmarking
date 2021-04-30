#!/bin/bash

MASTER_COUNT=`oc get nodes -l node-role.kubernetes.io/master | grep -v NAME | wc -l`
WORKER_COUNT=`oc get nodes -l node-role.kubernetes.io/worker | grep -v NAME | wc -l`
INFRA_COUNT=`oc get nodes -l node-role.kubernetes.io/infra | grep -v NAME | wc -l`

master=`oc get nodes -l node-role.kubernetes.io/master | grep -v NAME -m 1 | awk '{print $1}'`
worker=`oc get nodes -l node-role.kubernetes.io/worker | grep -v NAME -m 1 | awk '{print $1}'`
infra=`oc get nodes -l node-role.kubernetes.io/infra | grep -v NAME -m 1 | awk '{print $1}'`

MASTER_NODE_TYPE=`oc describe node $master | grep "node.kubernetes.io/instance-type" | grep -oP '=\K(.*)$'`
WORKER_NODE_TYPE=`oc describe node $worker | grep "node.kubernetes.io/instance-type" | grep -oP '=\K(.*)$'`
INFRA_NODE_TYPE=`oc describe node $infra | grep "node.kubernetes.io/instance-type" | grep -oP '=\K(.*)$'`


JSON_STRING=$( jq -n \
                  --arg mc "$MASTER_COUNT" \
                  --arg wc "$WORKER_COUNT" \
                  --arg ic "$INFRA_COUNT" \
                  --arg mt "$MASTER_NODE_TYPE" \
                  --arg wt "$WORKER_NODE_TYPE" \
                  --arg it "$INFRA_NODE_TYPE" \
                  '{MASTER_NODE_COUNT: $mc, WORKER_NODE_COUNT: $wc, INFRA_NODE_COUNT: $ic, MASTER_NODE_TYPE: $mt, WORKER_NODE_TYPE: $wt, INFRA_NODE_TYPE: $it}' )

echo $JSON_STRING
