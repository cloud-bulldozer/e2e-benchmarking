#!/usr/bin/env bash
set -e

source common.sh

get_number_of_pods
get_pods_per_namespace
run_test prometheus-sizing-churning.yml
