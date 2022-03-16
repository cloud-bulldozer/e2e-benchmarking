
#!/bin/bash

source ci/env.sh

test_choice=$@                                  #to accept inputs from command line

if [[ ${test_choice} != '' ]]; then
  echo -e "Running chosen tests: "
  for i in ${test_choice};do
    echo -e "${i}"
  done
  test_list=${test_choice}
else
  echo "Running full test"
  test_list=`cat ci/CI_test_list.yml`           #yml file contains the list of test scripts to run from different workloads
  echo -e  "$test_list\n\n"                         
fi

diff_list=`git diff --name-only origin/master`
echo -e "List of files changed : ${diff_list} \n"

cat > results.markdown << EOF
Results for e2e-benchmarking CI Tests
Workload                | Test                           | Result | Runtime  |
------------------------|--------------------------------|--------|----------|
EOF

test_rc=0
IFS=$'\n'
for test in ${test_list}; do            
  # Clear the /tmp/ripsaw-cli directory to avoid pip version conflicts due to existing temp files.
  rm -rf /tmp/ripsaw-cli
  start_time=`date`

  command=${test##*:}                                     #to extract the shell script name to run
  directory=${test%:*}                                    #to extract the workload directory name 
  echo $command
  
  echo -e "\n======================================================================"
  echo -e "     CI test for ${test}                    "
  echo -e "======================================================================\n"
  
  cd workloads/
  cd $directory
  echo $PWD

  (sleep $EACH_TEST_TIMEOUT; sudo pkill -f $command) &  #to kill a workload script if it doesn't execute within default test timeout ; runs in the background
  bash -c "$command"                                         #to execute each shell script

  EXIT_STATUS=$?
  if [ "$EXIT_STATUS" -eq "0" ]                         #to check if the workloads exit successfully or not
  then
      result="PASS"
  else
      result="FAIL"
      test_rc=1
  fi

  end_time=`date`
  duration=`date -ud@$(($(date -ud"$end_time" +%s)-$(date -ud"$start_time" +%s))) +%T`
  cd ../..
  
  echo "${directory} | ${command} | ${result} | ${duration}" >> results.markdown

done  

CURRENT_WORKER_COUNT=`oc get nodes --no-headers -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/workload!="" --ignore-not-found | grep -v NAME | wc -l`
if [[ ( $CURRENT_WORKER_COUNT != $ORIGINAL_WORKER_COUNT ) ]]; #check number of worker nodes and to bring it back
  then                                                        #to the original count after running all other tests 
    export SCALE=$ORIGINAL_WORKER_COUNT
    echo -e "\n======================================================================"
    echo -e "           Scaling down back to original worker count                    "
    echo -e "======================================================================\n"

    cd workloads/scale-perf/
    bash run_scale_fromgit.sh
    cd ../..    
  fi

cat results.markdown

exit $test_rc


