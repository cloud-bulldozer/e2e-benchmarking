#!/usr/bin/env bash

source ../../utils/common.sh
source ../../utils/benchmark-operator.sh
source env.sh

setup(){
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    echo [default] > aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> aws_credentials
    rosa login --env=${ROSA_ENVIRONMENT}
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    rosa whoami
    rosa verify quota
    rosa verify permissions
    echo "MANAGEMENT CLUSTER VERSION:"
    ocm list cluster $MGMT_CLUSTER_NAME
    echo "MANAGEMENT CLUSTER NODES:"
    kubectl get nodes
}

install(){
    echo "Install Hypershift Operator"
    aws s3api create-bucket --acl public-read --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION || true
    echo "Wait till S3 bucket is ready.."
    aws s3api wait bucket-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org 
    hypershift install --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org --oidc-storage-provider-s3-credentials aws_credentials --oidc-storage-provider-s3-region $AWS_REGION  --enable-ocp-cluster-monitoring
    echo "Wait till Operator is ready.."
    cm=""
    while [[ $cm != "oidc-storage-provider-s3-config" ]]
    do
        cm=$(oc get configmap -n kube-public oidc-storage-provider-s3-config --no-headers | awk '{print$1}' || true)
        echo "Hypershift Operator is not ready yet.."
        sleep 5
    done
}

create_cluster(){
    BASEDOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    echo $PULL_SECRET > pull-secret
    hypershift create cluster aws --name $HOSTED_CLUSTER_NAME --node-pool-replicas=$COMPUTE_WORKERS_NUMBER --base-domain $BASEDOMAIN --pull-secret pull-secret --aws-creds aws_credentials --region $AWS_REGION --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE --instance-type $COMPUTE_WORKERS_TYPE
    echo "Wait till hosted cluster got created and in progress.."
    kubectl wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    kubectl get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

create_empty_cluster(){
    BASEDOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    echo $PULL_SECRET > pull-secret
    hypershift create cluster none --name $HOSTED_CLUSTER_NAME --node-pool-replicas=0 --base-domain $BASEDOMAIN --pull-secret pull-secret --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE
    echo "Wait till hosted cluster got created and in progress.."
    kubectl wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    kubectl get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

postinstall(){
    echo "Wait till hosted cluster is ready.."
    kubectl wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

cleanup(){
    echo "Cleanup Hosted Cluster..."
    kubectl get hostedcluster -n clusters
    LIST_OF_HOSTED_CLUSTER=$(kubectl get hostedcluster -n clusters --no-headers | awk '{print$1}')
    for h in $LIST_OF_HOSTED_CLUSTER
    do
        echo "Destroy Hosted cluster $h ..."
        if [ "${NODEPOOL_SIZE}" == "0" ] ; then
            hypershift destroy cluster none --name $h
        else
            hypershift destroy cluster aws --name $h --aws-creds aws_credentials --region $AWS_REGION
        fi
        sleep 5 # pause a few secs before destroying next...
    done
    echo "Delete AWS s3 bucket..."
    for o in $(aws s3api list-objects --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org | jq -r '.Contents[].Key' | uniq)
    do 
        aws s3api delete-object --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --key=$o
    done    
    aws s3api delete-bucket --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org
    aws s3api wait bucket-not-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org
}