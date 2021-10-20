#!/usr/bin/env bash

install_cli() {
  ripsaw_tmp=/tmp/ripsaw-cli
  mkdir -p ${ripsaw_tmp}
  if [[ ! -f ${ripsaw_tmp}/bin/activate ]]; then
    python -m venv ${ripsaw_tmp}
  fi
  source ${ripsaw_tmp}/bin/activate
  pip3 install -U "git+https://github.com/cloud-bulldozer/benchmark-operator.git/#egg=ripsaw-cli&subdirectory=cli"
}

remove_cli() {
  deactivate
  rm -rf ${ripsaw_tmp}
}

############################################################################
# Deploys benchmark-operator using ripsaw CLI
# Arguments:
#   Benchmark-operator repository
#   Benchmark-operator branch
############################################################################
deploy_benchmark_operator() {
  install_cli
  ripsaw operator install --repo=${1} --branch=${2}
  deactivate
}

############################################################################
# Removes benchmark-operator using ripsaw CLI
# Arguments:
#   Benchmark-operator repository
#   Benchmark-operator branch
############################################################################
remove_benchmark_operator() {
  source ${ripsaw_tmp}/bin/activate
  ripsaw operator delete --repo=${1} --branch=${2}
  rm -rf ${ripsaw_tmp}
  remove_cli
}

############################################################################
# Creates a benchmark and wait for it to complete
# Arguments:
#   Benchmark CR
#   Timeout in seconds
############################################################################
run_benchmark() {
  source ${ripsaw_tmp}/bin/activate
  ripsaw benchmark run -f ${1} -t ${2}
  deactivate
}
