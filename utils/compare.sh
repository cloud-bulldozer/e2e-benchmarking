#!/usr/bin/env bash
#
# Handles benchmark-comparison execution

source common.sh

get_network_type() {
  if [[ $NETWORK_TYPE == "OVNKubernetes" ]]; then
    network_ns=openshift-ovn-kubernetes
  else
    network_ns=openshift-sdn
  fi
  echo $network_ns
}

check_metric_to_modify() {
  export div_by=1
  declare file_content=$( cat "${1}" )
  if [[ $file_content =~ "memory" ]]; then
   export div_by=1048576
  fi
  if [[ $file_content =~ "latency" ]]; then
    export div_by=1000
  fi
  if [[ $file_content =~ "byte" ]]; then
    export div_by=1000000
  fi
}

run_benchmark_comparison() {
  log "benchmark"
  compare_result=0

  # need ES_SERVER and COMPARISON_CONFIG env vars to be set
  if [[ -n ${ES_SERVER} ]] && [[ -n ${COMPARISON_CONFIG} ]]; then

    # install touchstone and set namespace based on network type
    log "Installing touchstone"
    install_touchstone
    network_ns=openshift-ovn-kubernetes
    get_network_type
    export TOUCHSTONE_NAMESPACE=${TOUCHSTONE_NAMESPACE:-"$network_ns"}

    # create output directory and variables for working and final output files
    # file type defaults to CSV but can be overriden to JSON via global env var
    res_output_dir="/tmp/${WORKLOAD}-${UUID}"
    mkdir -p ${res_output_dir}
    if [[ ${GEN_JSON} == true ]]; then
      file_type='json'
    else
      file_type='csv'
    fi
    export COMPARISON_OUTPUT=${PWD}/${WORKLOAD}-${UUID}.${file_type}
    final_file=${res_output_dir}/${UUID}.${file_type}
    echo "final $file_type $final_file"

    # if CONFIG_LOC is not set, clone the benchmark comparison repo to be used be default
    if [[ -z $CONFIG_LOC ]]; then
      git clone https://github.com/cloud-bulldozer/benchmark-comparison.git
    fi

    # iterate through all COMPARISON_CONFIG files
    for config in ${COMPARISON_CONFIG}
    do
      # config_loc can be custom but will be under benchmark-comparison by default
      if [[ -z $CONFIG_LOC ]]; then
        config_loc=benchmark-comparison/config/${config}
      else
        config_loc=$CONFIG_LOC/${config}
      fi
      echo "config ${config_loc}"
      check_metric_to_modify $config_loc
      COMPARISON_FILE="${res_output_dir}/${config}"
      envsubst < $config_loc > $COMPARISON_FILE
      echo "comparison output"

      # run baseline comparison if ES_SERVER_BASELINE and BASELINE_UUID are set
      if [[ -n ${ES_SERVER_BASELINE} ]] && [[ -n ${BASELINE_UUID} ]]; then
        log "Comparing with baseline"
        if ! compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" "${COMPARISON_FILE}"; then
          compare_result=$((${compare_result} + 1))
          log "Comparing with baseline for config file $config failed"
        fi

      # otherwise just run for current UUID
      else
        log "Querying results"
        compare ${ES_SERVER} ${UUID} "${COMPARISON_FILE}"
      fi

      # if file type is CSV, use python script to process working CSV into final CSV
      if [[ ${file_type} == 'csv' ]]; then
        log "python csv modifier"
        python $(dirname $(realpath ${BASH_SOURCE[0]}))/csv_modifier.py -c ${COMPARISON_OUTPUT} -o ${final_file}

        # generate a GSheet for the results if GSHEET_KEY_LOCATION and GEN_CSV are set
        if [[ -n ${GSHEET_KEY_LOCATION} ]] && [[ ${GEN_CSV} == true ]]; then
          gen_spreadsheet ${WORKLOAD} ${final_file} ${EMAIL_ID_FOR_RESULTS_SHEET} ${GSHEET_KEY_LOCATION}
        fi

      # otherwise simply copy the working JSON to the final JSON, as no modification is needed
      else
        log "copying over working JSON to final JSON"
        cp ${COMPARISON_OUTPUT} ${final_file}
      fi
    done

    # remove touchstone
    log "Removing touchstone"
    remove_touchstone
  fi

  # return an exit code of 1 if the comparison failed
  if [[ ${compare_result} -gt 0 ]]; then
    return 1
  fi
}

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
# Globals:
#   GEN_CSV Boolean for generating a CSV. Optional.
#   GEN_JSON Boolean for generating a JSON. Optional.
#   TOLERANCY_RULES Tolerancy config file path. Optional.
#   COMPARISON_ALIASES Benchmark-comparison aliases. Optional.
#   COMPARISON_OUTPUT Benchmark-comparison output file. Optional.
##############################################################################
compare() { 

  # base command
  cmd="touchstone_compare --database elasticsearch -url ${1} -u ${2} --config ${3}"

  # add arguments to base command based on function args and env globals
  if [[ ( -n ${TOLERANCY_RULES} ) && ( ${#2} > 40 ) ]]; then
    cmd+=" --tolerancy-rules ${TOLERANCY_RULES}"
  fi
  if [[ -n ${COMPARISON_ALIASES} ]]; then
    cmd+=" --alias ${COMPARISON_ALIASES}"
  fi
  if [[ ${GEN_CSV} == true ]] && [[ -n ${COMPARISON_OUTPUT} ]]; then
    cmd+=" -o csv --output-file ${COMPARISON_OUTPUT}"
  elif [[ ${GEN_JSON} == true ]] && [[ -n ${COMPARISON_OUTPUT} ]]; then
    cmd+=" -o json --output-file ${COMPARISON_OUTPUT}"
  fi
  if [[ -n ${COMPARISON_RC} ]]; then
    cmd+=" --rc ${COMPARISON_RC}"
  fi

  # run command and return result
  log "Running: ${cmd}"
  ${cmd}
  result=$?
  log "compare result: ${result}"
  return ${result}
}
