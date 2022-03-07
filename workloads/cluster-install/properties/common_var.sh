#General
export ORCHESTRATION_USER=root
export ORCHESTRATION_HOST=localhost
export OPENSHIFT_CLEANUP=true
export OPENSHIFT_INSTALL=true
export OPENSHIFT_POST_INSTALL=true
export OPENSHIFT_POST_CONFIG=true
export OPENSHIFT_DEBUG_CONFIG=true
export DESTROY_CLUSTER=true


# cluster version
#export OPENSHIFT_CLIENT_LOCATION= #required field
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=
#export OPENSHIFT_INSTALL_BINARY_URL= #required field


# post install
export ENABLE_DITTYBOPPER=true
export ENABLE_REMOTE_WRITE=false
export SINCGARS_REMOTE_WRITE_URL=
export KUBECONFIG_AUTH_DIR_PATH=
export SCALE_CI_BUILD_TRIGGER=
export SCALE_CI_BUILD_TRIGGER_URL=
export JENKINS_USER=
export JENKINS_API_TOKEN=
export JENKINS_ES_SERVER=

#cerberus
export CERBERUS_ENABLE=false
export KUBECONFIG_PATH=/root/.kube/config  #required field

#elasticsearch
#export ES_SERVER= #required field
#export ELASTIC_CURL_URL= 
#export ELASTIC_CURL_USER= 
#export ELASTIC_SERVER= 

# credentials
#export SSHKEY_TOKEN= #required field
#export OPENSHIFT_INSTALL_PULL_SECRET= #required field
#export OPENSHIFT_INSTALL_QUAY_REGISTRY_TOKEN= #required field
#export OPENSHIFT_INSTALL_IMAGE_REGISTRY= #required field
#export OPENSHIFT_INSTALL_REGISTRY_TOKEN= #required field
export OPENSHIFT_INSTALL_INSTALLER_FROM_SOURCE=false
#export OPENSHIFT_INSTALL_INSTALLER_FROM_SOURCE_VERSION=
export JOB_ITERATIONS=1

# rhacs
export RHACS_ENABLE=false