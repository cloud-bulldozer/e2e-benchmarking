#!/usr/bin/bash

function prepare_builds_file()
{
  project_name=`oc get project --no-headers | grep -m 1 conc-b | awk {'print $1'}`
  if [[ $project_name ]]; then
    bc_name=`oc get bc -n $project_name --no-headers | awk {'print $1'}`
    running_build_file="running-builds.json"
    # generate running-builds.json on the fly
    printf '%s\n' "[" > "${running_build_file}"
    proj_substring=${project_name::${#project_name}-1}
    for (( c=1; c<"${MAX_CONC_BUILDS}"; c++ ))
    do
      if [[ "$c" == $((MAX_CONC_BUILDS - 1)) ]]; then
        printf '%s\n' "{\"namespace\":\"$proj_substring${c}\", \"name\":\"$bc_name\"}" >> "${running_build_file}"
      else
        printf '%s\n' "{\"namespace\":\"$proj_substring${c}\", \"name\":\"$bc_name\"}," >> "${running_build_file}"
      fi
    done
    printf '%s' "]" >> "${running_build_file}"
  fi
}


function install_svt_repo() {
  rm -rf svt
  git clone --single-branch --branch ${build_test_branch} ${build_test_repo} --depth 1
  pip3 install future pytimeparse
}

function run_builds() {
  
  for i in "${build_array[@]}"
  do
    log "running $i $1 concurrent builds"
    fileName="conc_builds_$1.out"
    python3 svt/openshift_performance/ose3_perf/scripts/build_test.py -z -a -n 2 -r $i -f running-builds.json >> $fileName 2>&1
    sleep 10
  done
}

function wait_for_running_builds() {
  running=`oc get pods -A --no-headers | grep svt-$1 | grep Running | wc -l`
  while [ $running -ne 0 ]; do
    sleep 15
    running=`oc get pods -A | grep svt-$1 | grep Running | wc -l`
    log "$running pods are still running"
  done

}

function run_build_workload() {
  app=$1
  export APP_SUBNAME=$app
  rm -rf conc_builds_$app.out
  . ./builds/$app.sh

  run_workload kube-burner-crd.yaml
  sleep 15
  wait_for_running_builds $app
  sleep 10

  prepare_builds_file conc_builds_$app.out
  run_builds $app
  proj=$app

  echo "================ Average times for $proj app =================" >> conc_builds_results.out
  grep "Average build time, all good builds" conc_builds_$proj.out >> conc_builds_results.out
  grep "Average push time, all good builds" conc_builds_$proj.out >> conc_builds_results.out
  grep "Good builds included in stats" conc_builds_$proj.out >> conc_builds_results.out
  echo "==============================================================" >> conc_builds_results.out
  # have to clean up to be able to run with new configmap/kube-burner with same uuid

  cat conc_builds_$proj.out
  cleanup

}
