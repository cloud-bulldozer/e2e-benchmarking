#!/usr/bin/env bash
#
# Handles benchmark-comparison execution


install_touchstone() {
  touchstone_tmp=$(mktemp -d)
  python3 -m venv ${touchstone_tmp}
  source ${touchstone_tmp}/bin/activate
  pip3 install -qq git+https://github.com/cloud-bulldozer/benchmark-comparison.git
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
#   Benchmark-comparison configuration file path.
#   Output format
# Globals
#   TOLERANCY_RULES Tolerancy config file path. Optional
#   COMPARISON_ALIASES Benchmark-comparison aliases. Optional
#   COMPARISON_OUTPUT Benchmark-comparison output file. Optional
##############################################################################
compare() { 
  cmd="touchstone_compare --database elasticsearch -url ${1} -u ${2} --config ${3} -o ${4}"
  if [[ ( -n ${TOLERANCY_RULES} ) && ( ${#2} > 40 ) ]]; then
    cmd+=" --tolerancy-rules ${TOLERANCY_RULES}"
  fi
  if [[ -n ${COMPARISON_ALIASES} ]]; then
    cmd+=" --alias ${COMPARISON_ALIASES}"
  fi
  if [[ -n ${COMPARISON_FORMAT} ]] && [[ -n ${COMPARISON_OUTPUT} ]]; then
    cmd+=" --output-file ${COMPARISON_OUTPUT}"
  fi
  if [[ -n ${COMPARISON_RC} ]]; then
    cmd+=" --rc ${COMPARISON_RC}"
  fi
  log "Running: ${cmd}"
  ${cmd}
}
