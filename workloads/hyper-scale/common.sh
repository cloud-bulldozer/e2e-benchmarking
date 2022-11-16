#!/usr/bin/env bash
set -x

source env.sh
TEMP_DIR=`mktemp -d`

prep(){
    if [[ -z $(go version) ]]; then
        curl -L https://go.dev/dl/go1.18.2.linux-amd64.tar.gz -o go1.18.2.linux-amd64.tar.gz
        tar -C ${TEMP_DIR}/ -xzf go1.18.2.linux-amd64.tar.gz
        export PATH=${TEMP_DIR}/go/bin:$PATH
    fi
    if [[ ${HYPERSHIFT_CLI_INSTALL} == "true" ]]; then
        echo "Building Hypershift binaries locally.."
        git clone -q --depth=1 --single-branch --branch ${HYPERSHIFT_CLI_VERSION} ${HYPERSHIFT_CLI_FORK} -v $TEMP_DIR/hypershift
        pushd $TEMP_DIR/hypershift
        make build
        export PATH=$TEMP_DIR/hypershift/bin:$PATH
        popd
    fi
    if [[ -z $(rosa version)  ]]; then
        mkdir -p ${TEMP_DIR}/bin/
        sudo curl -L $(curl -s https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa-linux-amd64\") | .browser_download_url") --output ${TEMP_DIR}/bin/rosa
        sudo curl -L $(curl -s https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output ${TEMP_DIR}/bin/ocm
        chmod +x ${TEMP_DIR}/bin/rosa && chmod +x ${TEMP_DIR}/bin/ocm
        export PATH=${TEMP_DIR}/bin:$PATH
    fi
    if [[ -z $(oc version) ]]; then
        rosa download openshift-client
        tar xzvf openshift-client-linux.tar.gz
        mv oc kubectl ${TEMP_DIR}/bin/
    fi
    if [[ -z $(aws --version) ]]; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
    fi

}

setup(){
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'| cut -c 1-13)
    export MGMT_BASEDOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    export MGMT_AWS_HZ_ID=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${MGMT_BASEDOMAIN}'.")' | jq -r '.Id')
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        # check given Hypershift operator version is >= 4.12
        OP_REL_CHECK=$(echo "$(echo $HYPERSHIFT_OPERATOR_IMAGE | awk -F: '{print$2}' | cut -c 1-4) >= 4.12" |bc -l)
        # check given HostedCluster release is >= 4.12
        REL_CHECK=$(echo "$(echo $RELEASE_IMAGE | awk -F: '{print$2}' | cut -c 1-4) >= 4.12" |bc -l)
        if [[ $REL_CHECK == 1 ]] || [[ "$RELEASE_IMAGE" == "" && $(echo $HYPERSHIFT_OPERATOR_IMAGE | awk -F: '{print$2}' | cut -c 1-4) == "late" || $OP_REL_CHECK == 1 ]]; then
            echo "Create external DNS for this iteration.."
            export BASEDOMAIN=hyp.${MGMT_BASEDOMAIN}
            AWS_HZ=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'${BASEDOMAIN}'.")')
            if [[ ${AWS_HZ} == "" ]]; then
                AWS_HZ_ID=$(aws route53 create-hosted-zone --name $BASEDOMAIN --caller-reference ${HOSTED_CLUSTER_NAME}-$(echo $(uuidgen) | cut -c 1-5) | jq -r '.HostedZone.Id')
                DS_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $AWS_HZ_ID  | jq -r '.ResourceRecordSets[] | select(.Name=="'"$BASEDOMAIN"'.") | select(.Type=="NS")' | jq -c '.ResourceRecords')
                aws route53 change-resource-record-sets --hosted-zone-id  $MGMT_AWS_HZ_ID \
                    --change-batch '{ "Comment": "Creating a record set" , "Changes": [{"Action": "CREATE", "ResourceRecordSet": {"Name": "'"$BASEDOMAIN"'", "Type": "NS", "TTL": 300, "ResourceRecords" : '"$DS_VALUE"'}}]}'
            fi
        else
            echo "external-dns options can be set only when hypershift cluster release is >= 4.12"
            exit 1
        fi
    else
        export BASEDOMAIN=${MGMT_BASEDOMAIN}
    fi
    export AWS_REGION=us-west-2
    echo [default] > aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> aws_credentials
    rosa login --env=${ROSA_ENVIRONMENT}
    ocm login --url=https://api.stage.openshift.com --token="${ROSA_TOKEN}"
    hypershift --version
    oc version --client
    rosa whoami
    rosa verify quota
    rosa verify permissions
}

pre_flight_checks(){
    echo "Pre flight checks started"
    export MULTI_AZ=$(rosa describe cluster -c $MGMT_CLUSTER_NAME -o json | jq -r [.multi_az] | jq -r .[])

    if [[ "${MULTI_AZ}" == "true" ]]; then
        echo "Pre flight checks passed"
    else
        echo "Pre flight checks failed, cluster should be multi-az enabled"
        rm -rf $TEMP_DIR || true
        exit 1
    fi
}

install(){
    echo "Create S3 bucket and route53 doamin.."
    aws s3api create-bucket --acl public-read --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION || true
    aws route53 create-hosted-zone --name $BASEDOMAIN --caller-reference perfscale-ci-$(date --iso-8601=seconds) || true
    echo "Wait till S3 bucket is ready.."
    aws s3api wait bucket-exists --bucket $MGMT_CLUSTER_NAME-aws-rhperfscale-org 
    HO_IMAGE_ARG=""
    HCP_P_MONITOR=""
    EXT_DNS_ARG=""    
    if [[ $HYPERSHIFT_OPERATOR_IMAGE != "" ]]; then
            HO_IMAGE_ARG="--hypershift-image $HYPERSHIFT_OPERATOR_IMAGE"
    fi
    if [[ $HCP_PLATFORM_MONITORING == "true" ]]; then
        HCP_P_MONITOR="--platform-monitoring $HCP_PLATFORM_MONITORING"
    fi
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-provider=aws --external-dns-credentials=aws_credentials --external-dns-domain-filter=$BASEDOMAIN"
    fi
    hypershift install  \
        --oidc-storage-provider-s3-bucket-name $MGMT_CLUSTER_NAME-aws-rhperfscale-org \
        --oidc-storage-provider-s3-credentials aws_credentials \
        --oidc-storage-provider-s3-region $AWS_REGION \
        --metrics-set All $EXT_DNS_ARG $HCP_P_MONITOR $HO_IMAGE_ARG

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
    ZONES=""
    if [[ $HC_MULTI_AZ == "true" ]]; then
        ZONES="--zones ${AWS_REGION}a,${AWS_REGION}b,${AWS_REGION}c"
    fi
    EXT_DNS_ARG=""
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-domain=$BASEDOMAIN"
    fi    
    hypershift create cluster aws \
        --name $HOSTED_CLUSTER_NAME \
        --additional-tags "mgmt-cluster=${MGMT_CLUSTER_NAME}" \
        --node-pool-replicas=$COMPUTE_WORKERS_NUMBER \
        --base-domain $BASEDOMAIN \
        --pull-secret pull-secret \
        --aws-creds aws_credentials \
        --region $AWS_REGION \
        --control-plane-availability-policy $CONTROLPLANE_REPLICA_TYPE \
        --infra-availability-policy $INFRA_REPLICA_TYPE \
        --network-type $NETWORK_TYPE \
        --instance-type $COMPUTE_WORKERS_TYPE \
        --endpoint-access=Public ${EXT_DNS_ARG} ${RELEASE} ${CPO_IMAGE_ARG} ${ZONES}

    echo "Wait till hosted cluster got created and in progress.."
    oc wait --for=condition=available=false --timeout=60s hostedcluster -n clusters $HOSTED_CLUSTER_NAME
    oc get hostedcluster -n clusters $HOSTED_CLUSTER_NAME
}

create_empty_cluster(){
    echo $PULL_SECRET > pull-secret
    EXT_DNS_ARG=""
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        EXT_DNS_ARG="--external-dns-domain=$BASEDOMAIN"
    fi   
    hypershift create cluster none --name $HOSTED_CLUSTER_NAME \
        --node-pool-replicas=0 \
        --base-domain $BASEDOMAIN \
        --pull-secret pull-secret \
        --control-plane-availability-policy $CONTROLPLANE_REPLICA_TYPE \
        --infra-availability-policy $INFRA_REPLICA_TYPE \
        --network-type $NETWORK_TYPE \
        --endpoint-access=Public ${EXT_DNS_ARG}
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
        if [[ $HC_MULTI_AZ == "true" ]]; then
            NODEPOOL_SIZE=$((3*$NODEPOOL_SIZE))
        fi
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
            hypershift destroy cluster aws --name $h --aws-creds aws_credentials --region $AWS_REGION --destroy-cloud-resources
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
    echo "Delete external dns records and hostedzone"
    ROUTE_ID=$(aws route53 list-hosted-zones --output text --query HostedZones | grep $BASEDOMAIN | grep hyp | grep -v terraform | awk '{print$2}')
    for _ID in $ROUTE_ID; 
    do
        aws route53 list-resource-record-sets --hosted-zone-id $_ID --output json | jq -c '.ResourceRecordSets[]' |
        while read -r resourcerecordset; do
            read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
            if [ $type != "NS" -a $type != "SOA" ]; then
                aws route53 change-resource-record-sets --hosted-zone-id $_ID \
                    --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":'"$resourcerecordset"'}]}' \
                    --output text --query 'ChangeInfo.Id'
            fi
        done
        aws route53 delete-hosted-zone --id=$_ID || true
    done
    if [[ $HC_EXTERNAL_DNS == "true" ]]; then
        echo "Delete recordset in mgmt hostedzone"
        RS_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $MGMT_AWS_HZ_ID | jq -c '.ResourceRecordSets[] | select(.Name=="'"$BASEDOMAIN"'.") | select(.Type=="NS")')
        aws route53 change-resource-record-sets --hosted-zone-id $MGMT_AWS_HZ_ID \
            --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"$RS_VALUE"'}]}' \
            --output text --query 'ChangeInfo.Id'
    fi
    rm -f *-admin-kubeconfig || true
    rm -f pull-secret || true
    rm -rf kube-burner.tar.gz|| true
    rm -f hypershift-metrics.yaml baseconfig.yml || true
    rm -f aws_credentials || true
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
        sudo tar -xvzf kube-burner.tar.gz -C ${TEMP_DIR}/bin/
    fi
    export MGMT_CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export HOSTED_CLUSTER_NS="clusters-$HOSTED_CLUSTER_NAME"
    envsubst < ../kube-burner/metrics-profiles/hypershift-metrics.yaml > hypershift-metrics.yaml
    envsubst < ../kube-burner/workloads/managed-services/baseconfig.yml > baseconfig.yml
    echo "Running kube-burner index.."
    kube-burner index --uuid=${_uuid} --prometheus-url=${THANOS_QUERIER_URL} --start=$START_TIME --end=$END_TIME --step 2m --metrics-profile hypershift-metrics.yaml --config baseconfig.yml
    echo "Finished indexing results for $HOSTED_CLUSTER_NAME"
}
