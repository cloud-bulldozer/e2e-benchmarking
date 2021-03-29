#!/usr/bin/env bash
set -e

source common.sh
# How many pods to create in each node
export PODS_PER_NODE=50
# How often pod churning happens
export POD_CHURNING_PERIOD=15m
# Number of namespaces
export NUMBER_OF_NS=8
export JOB_PAUSE=${JOB_PAUSE:-125m}

get_number_of_pods
get_pods_per_namespace
run_test prometheus-sizing-churning.yml
