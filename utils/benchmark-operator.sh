#!/usr/bin/env bash

install_cli() {
  ripsaw_tmp=/tmp/ripsaw-cli
  mkdir -p ${ripsaw_tmp}
  if [[ ! -f ${ripsaw_tmp}/bin/activate ]]; then
      if [[ "${isBareMetal}" == "true" ]]; then
        python3.8 -m venv ${ripsaw_tmp}
      else
        python -m venv ${ripsaw_tmp}
      fi
  fi
  source ${ripsaw_tmp}/bin/activate
  pip3 install -qq -U "git+https://github.com/cloud-bulldozer/benchmark-operator.git/#egg=ripsaw-cli&subdirectory=cli"
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
  if ! ripsaw benchmark run -f ${1} -t ${2}; then
    log "Benchmark failed, dumping workload more recent logs"
    local tmp_dir=$(mktemp -d)
    kubectl -n benchmark-operator get pod -l benchmark-uuid=${UUID}
    for pod in $(kubectl -n benchmark-operator get pod -l benchmark-uuid=${UUID} -o custom-columns="name:.metadata.name" --no-headers); do
      pod_log=${tmp_dir}/${pod}.log
      log "Writing pod logs in ${pod_log}"
      kubectl logs --prefix --tail=30 ${pod}
      kubectl logs --prefix --tail=-1 ${pod} >> ${pod_log}
    done
    remove_cli
    exit 1
  fi
  deactivate
}
