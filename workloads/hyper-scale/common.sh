#!/usr/bin/env bash
set -x

source env.sh

prep(){
    if [[ -z $(go version) ]]; then
        curl -L https://go.dev/dl/go1.18.2.linux-amd64.tar.gz -o go1.18.2.linux-amd64.tar.gz
        tar -C /usr/local -xzf go1.18.2.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
    fi
    if [[ ${HYPERSHIFT_CLI_INSTALL} != "false" ]]; then
        echo "Remove current Hypershift CLI directory.."
        sudo rm -rf hypershift || true
        sudo rm /usr/local/bin/hypershift || true
        git clone -q --depth=1 --single-branch --branch ${HYPERSHIFT_CLI_VERSION} ${HYPERSHIFT_CLI_FORK}    
        pushd hypershift
        make build
        sudo cp bin/hypershift /usr/local/bin
        popd
    fi
    if [[ -z $(rosa version)  ]]; then
        sudo curl -L $(curl -s https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa-linux-amd64\") | .browser_download_url") --output /usr/local/bin/rosa
        sudo curl -L $(curl -s https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output /usr/local/bin/ocm
        sudo chmod +x /usr/local/bin/rosa && chmod +x /usr/local/bin/ocm
    fi
    if [[ -z $(oc help) ]]; then
        rosa download openshift-client
        tar xzvf openshift-client-linux.tar.gz
        sudo mv oc kubectl /usr/local/bin/
    fi
    if [[ -z $(aws --version) ]]; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
    fi

}

setup(){
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'| cut -c 1-13)
    export BASEDOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    export AWS_REGION=us-west-2
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
    HO_IMAGE_ARG=""
    if [[ $HYPERSHIFT_OPERATOR_IMAGE != "" ]]; then
            HO_IMAGE_ARG="--hypershift-image $HYPERSHIFT_OPERATOR_IMAGE"
    fi    
    hypershift install $HO_IMAGE_ARG --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org --oidc-storage-provider-s3-credentials aws_credentials --oidc-storage-provider-s3-region $AWS_REGION  --enable-ocp-cluster-monitoring --metrics-set=All
    echo "Wait till Operator is ready.."
    kubectl wait --for=condition=available --timeout=600s deployments/operator -n hypershift
}

create_cluster(){
    echo $PULL_SECRET > pull-secret
    CPO_IMAGE_ARG=""
    if [[ $CPO_IMAGE != "" ]] ; then
        CPO_IMAGE_ARG="--control-plane-operator-image=$CPO_IMAGE"
    fi    
    RELEASE=""
    if [[ $RELEASE_IMAGE != "" ]]; then
        RELEASE="--release-image=$RELEASE_IMAGE"
    fi
    hypershift create cluster aws --name $HOSTED_CLUSTER_NAME --node-pool-replicas=$COMPUTE_WORKERS_NUMBER --base-domain $BASEDOMAIN --pull-secret pull-secret --aws-creds aws_credentials --region $AWS_REGION --control-plane-availability-policy $REPLICA_TYPE --network-type $NETWORK_TYPE --instance-type $COMPUTE_WORKERS_TYPE  ${RELEASE} ${CPO_IMAGE_ARG}
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
    if [ "${NODEPOOL_SIZE}" != "0" ] ; then
        kubectl get secret -n clusters $HOSTED_CLUSTER_NAME-admin-kubeconfig -o json | jq -r '.data.kubeconfig' | base64 -d > ./$HOSTED_CLUSTER_NAME-admin-kubeconfig
        itr=0
        while [ $itr -lt 12 ]
        do
            node=$(oc get nodes --kubeconfig $HOSTED_CLUSTER_NAME-admin-kubeconfig | grep worker | grep -i ready | grep -iv notready | wc -l)
            if [[ $node == $NODEPOOL_SIZE ]]; then
                echo "All nodes are ready in cluster - $HOSTED_CLUSTER_NAME ..."
                break
            else
                echo "Available node(s) is(are) $node, still waiting for remaining nodes"
                sleep 300
            fi
            itr=$((itr+1))
        done
        if [[ $node != $NODEPOOL_SIZE ]]; then
            echo "All nodes are not ready in cluster - $HOSTED_CLUSTER_NAME ..."
            exit 1
        fi
        update_fw
    fi
}

update_fw(){
    echo "Get AWS VPC and security groups.."
    CLUSTER_VPC=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PrivateIpAddress,PublicIpAddress, PrivateDnsName, VpcId]' --output text | column -t | grep ${HOSTED_CLUSTER_NAME} | awk '{print $7}' | grep -v '^$' | sort -u)
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${CLUSTER_VPC}" --output json | jq -r .SecurityGroups[].GroupId)
    for group in $SECURITY_GROUPS
    do
        echo "Add rules to group $group.."
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 22 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 2022 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 20000-31000 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol udp --port 20000-31000 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol tcp --port 32768-60999 --cidr 0.0.0.0/0
        aws ec2 authorize-security-group-ingress --group-id $group --protocol udp --port 32768-60999 --cidr 0.0.0.0/0
    done
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

index_mgmt_cluster_stat(){
    _uuid=$(uuidgen)
    echo "################################################################################"
    echo "Indexing Management cluster stat on creation of $HOSTED_CLUSTER_NAME UUID: ${_uuid}"
    echo "################################################################################"
    echo "Installing kube-burner"
    KB_EXISTS=$(which kube-burner)
    if [ $? -ne 0 ]; then
        export KUBE_BURNER_RELEASE=${KUBE_BURNER_RELEASE:-0.16}
        curl -L https://github.com/cloud-bulldozer/kube-burner/releases/download/v${KUBE_BURNER_RELEASE}/kube-burner-${KUBE_BURNER_RELEASE}-Linux-x86_64.tar.gz -o kube-burner.tar.gz
        sudo tar -xvzf kube-burner.tar.gz -C /usr/local/bin/
    fi
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export HOSTED_CLUSTER_NS="clusters-$HOSTED_CLUSTER_NAME"
    envsubst < ../kube-burner/metrics-profiles/hypershift-metrics.yaml > hypershift-metrics.yaml
    envsubst < ../kube-burner/workloads/managed-services/baseconfig.yml > baseconfig.yml
    echo "Running kube-burner index.."
    kube-burner index --uuid=${_uuid} --prometheus-url=${THANOS_QUERIER_URL} --start=$START_TIME --end=$END_TIME --step 2m --metrics-profile hypershift-metrics.yaml --config baseconfig.yml
    echo "Finished indexing results for $HOSTED_CLUSTER_NAME"
}