#!/usr/bin/env bash

source env.sh

prep(){
    if [[ -z $(go version) ]]; then
        curl -L https://go.dev/dl/go1.17.6.linux-amd64.tar.gz -o go1.17.6.linux-amd64.tar.gz
        tar -C /usr/local -xzf go1.17.6.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        git clone --branch main https://github.com/openshift/hypershift
        pushd hypershift
        make build
        popd 
        cp ./hypershift/bin/hypershift /usr/local/bin/ -u
        curl -L $(curl -s https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa-linux-amd64\") | .browser_download_url") --output /usr/local/bin/rosa
        curl -L $(curl -s https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output /usr/local/bin/ocm
        chmod +x /usr/local/bin/rosa && chmod +x /usr/local/bin/ocm
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
    fi
}
setup(){
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'| cut -c 1-13)
    export BASEDOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    echo [default] > aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> aws_credentials
    rosa login --env=${ROSA_ENVIRONMENT}
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    rosa whoami
    rosa verify quota
    rosa verify permissions
}

install(){
    echo "Create S3 bucket and route53 doamin.."
    aws s3api create-bucket --acl public-read --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION || true
    aws route53 create-hosted-zone --name $BASEDOMAIN --caller-reference perfscale-ci-$(date --iso-8601=seconds) || true
    echo "Wait till S3 bucket is ready.."
    aws s3api wait bucket-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org 
    hypershift install --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org --oidc-storage-provider-s3-credentials aws_credentials --oidc-storage-provider-s3-region $AWS_REGION  --enable-ocp-cluster-monitoring
    echo "Wait till Operator is ready.."
    cm=""
    while [[ $cm != "oidc-storage-provider-s3-config" ]]
    do
        cm=$(oc get configmap -n kube-public oidc-storage-provider-s3-config --no-headers | awk '{print$1}' || true)
        echo "Hypershift Operator is not ready yet..Retrying after few seconds"
        sleep 5
    done
}

create_cluster(){
    echo $PULL_SECRET > pull-secret
    RELEASE=""
    if [[ $RELEASE_IMAGE != "" ]]; then
        RELEASE="--release-image=$RELEASE_IMAGE"
    fi
    hypershift create cluster aws --name $HOSTED_CLUSTER_NAME --node-pool-replicas=$COMPUTE_WORKERS_NUMBER --base-domain $BASEDOMAIN --pull-secret pull-secret --aws-creds aws_credentials --region $AWS_REGION --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE --instance-type $COMPUTE_WORKERS_TYPE  $RELEASE# --control-plane-operator-image=quay.io/hypershift/hypershift:latest
    echo "Wait till hosted cluster got created and in progress.."
    oc wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    oc get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

create_empty_cluster(){
    echo $PULL_SECRET > pull-secret
    hypershift create cluster none --name $HOSTED_CLUSTER_NAME --node-pool-replicas=0 --base-domain $BASEDOMAIN --pull-secret pull-secret --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE
    echo "Wait till hosted cluster got created and in progress.."
    oc wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    oc get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

postinstall(){
    echo "Wait till hosted cluster is ready.."
    oc wait --for=condition=available --timeout=3600s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

cleanup(){
    echo "Cleanup Hosted Cluster..."
    oc get hostedcluster -n clusters
    LIST_OF_HOSTED_CLUSTER=$(oc get hostedcluster -n clusters --no-headers | awk '{print$1}')
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
    sleep 10
    ROUTE_ID=$(aws route53 list-hosted-zones --output text --query HostedZones | grep $BASEDOMAIN | grep -v terraform | awk '{print$2}' | awk -F/ '{print$3}')
    for id in $ROUTE_ID; do aws route53 delete-hosted-zone --id=$id || true ; done
}