#!/usr/bin/env bash
#
# Handles benchmark-comparison execution


install_touchstone() {
  touchstone_tmp=$(mktemp -d)
  python -m venv ${touchstone_tmp}
  source ${touchstone_tmp}/bin/activate
  pip3 install git+https://github.com/cloud-bulldozer/benchmark-comparison.git
}

remove_touchstone() {
  deactivate
  rm -rf "${touchstone_tmp}"
}

##############################################################################
# Run benchmark-comparison to compare two different datasets
# Arguments:
#   Dataset URL, in case of passing more than one, they must be quoted.
#   Dataset UUIDs, in case of passing more than one, they must be quoted.
#   Benchmark-comparison configuration file path
#   Tolerancy-rules configuration file path. Optional. 
##############################################################################
compare(){ 
  install_touchstone
  cmd="touchstone_compare --database elasticsearch -url ${1} -u ${2} -o yaml --config ${3}"
  if [[ -n ${4} ]]; then
    cmd+=" --tolerancy-rules ${4}" 
  fi
  echo ${cmd}
  ${cmd}
  remove_touchstone
}
