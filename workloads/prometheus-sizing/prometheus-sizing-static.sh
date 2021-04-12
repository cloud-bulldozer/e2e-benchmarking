#!/usr/bin/env bash
set -e

source common.sh

get_number_of_pods
run_test prometheus-sizing-static.yml
