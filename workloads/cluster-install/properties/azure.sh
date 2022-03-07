export OPENSHIFT_INSTALL_APIVERSION=v1
export OPENSHIFT_INSTALL_SSH_PUB_KEY_FILE=/root/.ssh/id_rsa.pub
export GOPATH=/root/.go
#export OPENSHIFT_BASE_DOMAIN= #required field
#export OPENSHIFT_CLUSTER_NAME= #required field
export OPENSHIFT_MASTER_COUNT=3
export OPENSHIFT_WORKER_COUNT=3
export OPENSHIFT_MASTER_VM_SIZE=Standard_D4s_v3
export OPENSHIFT_WORKER_VM_SIZE=Standard_D2s_v3
export OPENSHIFT_MASTER_ROOT_VOLUME_SIZE=1024
export OPENSHIFT_WORKER_ROOT_VOLUME_SIZE=128
export OPENSHIFT_NETWORK_TYPE=OpenShiftSDN
export OPENSHIFT_CIDR=10.128.0.0/14
export OPENSHIFT_MACHINE_CIDR=10.0.0.0/16
export OPENSHIFT_SERVICE_NETWORK=172.30.0.0/16
export OPENSHIFT_HOST_PREFIX=23
export OPENSHIFT_POST_INSTALL_POLL_ATTEMPTS=600
export OPENSHIFT_TOGGLE_INFRA_NODE=true
export OPENSHIFT_TOGGLE_WORKLOAD_NODE=true
export MACHINESET_METADATA_LABEL_PREFIX=machine.openshift.io
export OPENSHIFT_INFRA_NODE_VM_SIZE=Standard_D2s_v3
export OPENSHIFT_WORKLOAD_NODE_VM_SIZE=Standard_D2s_v3
export OPENSHIFT_INFRA_NODE_VOLUME_SIZE=64
export OPENSHIFT_INFRA_NODE_VOLUME_TYPE=Premium_LRS
export OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=64
export OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE=Premium_LRS
export OPENSHIFT_PROMETHEUS_RETENTION_PERIOD=15d
export OPENSHIFT_PROMETHEUS_STORAGE_CLASS=Premium_LRS
export OPENSHIFT_PROMETHEUS_STORAGE_SIZE=5Gi
export OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=Premium_LRS
export OPENSHIFT_ALERTMANAGER_STORAGE_SIZE=1Gi


# Azure specific
#export AZURE_SUBSCRIPTION_ID= #required field
#export AZURE_TENANT_ID= #required field
#export AZURE_SERVICE_PRINCIPAL_CLIENT_ID= #required field
#export AZURE_SERVICE_PRINCIPAL_CLIENT_SECRET= #required field
#export AZURE_BASE_DOMAIN_RESOURCE_GROUP_NAME= #required field
export AZURE_REGION="centralus"