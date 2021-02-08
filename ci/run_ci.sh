
#!/bin/bash

#set -x

source ci/env.sh

#git checkout /pr/<pr-no>   the pr number can be accepted as input or obtained from pr_list

diff_list=`git diff --name-only origin/master`

if [ -z "$diff_list" ]
then
      echo "No changes noticed , exiting"
      exit 0
else
      echo -e " \nList of files changed : ${diff_list} \n"
fi

cat > results.markdown << EOF
Results for e2e-benchmarking CI Tests
Workload                | Test                           | Result | Runtime  |
------------------------|--------------------------------|--------|----------|
EOF

test_list=`cat ci/CI_test_list.yml`           #yml file contains the list of test scripts to run from different workloads

echo -e  "$test_list\n\n"                         

for i in ${test_list}; do            

  start_time=`date`

  command=${i##*:}                            #to extract the shell script name to run
  directory=${i%:*}                           #to extract the workload directory name 
  echo $directory  $command

  figlet "CI test for ${i}"                   # figlet gives a heading for each test

  cd workloads/
  cd $directory
  echo $PWD

  (sleep 600s; sudo pkill -f $command) &      #to kill a workload script if it doesn't execute within 500s ; runs in the background
  bash $command                               #to execute each shell script

  EXIT_STATUS=$?
  if [ "$EXIT_STATUS" -eq "0" ]                #to check if the workloads exit successfully or not
  then
      result="PASS"
  else
      result="FAIL"
  fi

  end_time=`date`
  duration=`date -ud@$(($(date -ud"$end_time" +%s)-$(date -ud"$start_time" +%s))) +%T`
  cd ../..
  
  echo "${directory} | ${command} | ${result} | ${duration}" >> results.markdown

done  

cat results.markdown

