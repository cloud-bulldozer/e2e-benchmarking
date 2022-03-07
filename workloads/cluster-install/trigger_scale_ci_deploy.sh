#!/bin/bash

export PLATFORM=$1
export RUNS=$2

chmod +x properties/${PLATFORM}.sh 
source properties/${PLATFORM}.sh        #to initialize the required env variables
source properties/common_var.sh

git clone https://github.com/cloud-bulldozer/scale-ci-deploy.git
cd scale-ci-deploy


if [[ ${PLATFORM} == '' ]]; then
  echo -e "Wrong usage, please enter a platform choice: aws/azure/gcp"
  exit 1

# Create output file
echo "Cluster Install Timings from openshift-install.log file -- \n" > install_logs.log

test_rc=0

for i in ${1..$RUNS}; do
  export _PLATFORM=$PLATFORM                                           #needed to check the platform in common.sh
  source CI/common.sh                                              # to check if all environment variables are set accordingly
    
  echo -e "\n======================================================================"
  echo -e "     Installing cluster using scale-ci-deploy                           "
  echo -e "======================================================================\n"
  
  # Create inventory File:
  echo "[orchestration]" > inventory
  echo "${ORCHESTRATION_HOST}" >> inventory

  export ANSIBLE_FORCE_COLOR=true 
  ansible-playbook -v -i inventory OCP-4.X/deploy-cluster.yml -e platform=${PLATFORM} 

  EXIT_STATUS=$?
  if [ "$EXIT_STATUS" -eq "0" ]                                    #to check if the test exits successfully or not
  then
      result="Installation: ${i} Completed! \n Copying Install Timings..... "
      tail /${ORCHESTRATION_USER}/scale-ci-${OPENSHIFT_CLUSTER_NAME}-${PLATFORM}/.openshift_install.log >> install_logs.log
  else
      result="Installation: ${i} Failed!"
      test_rc=1
  fi
  
  ##Destroy cluster, auto cleanup##
  if [[ ${DESTROY_CLUSTER} == "true" ]]; then  
    ansible-playbook -v -i inventory OCP-4.X/destroy-cluster.yml -e platform=${PLATFORM} 
   
    EXIT_STATUS=$?
    if [ "$EXIT_STATUS" -eq "0" ]                                    #to check if the test exits successfully or not
    then
      echo "Cluster Successfully destroyed!"
    else
      test_rc=1
      echo "Failed to destroy cluster!"
    fi
  fi
done 

cat install_logs.log
exit test_rc