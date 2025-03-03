#!/usr/bin/env bash
set -x

export AWS_REGION=${AWS_REGION:-us-west-2}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}

TEMP_DIR=`mktemp -d`

prep_aws(){
    if [[ -z $(go version) ]]; then
        curl -L https://go.dev/dl/go1.18.2.linux-amd64.tar.gz -o go1.18.2.linux-amd64.tar.gz
        tar -C ${TEMP_DIR}/ -xzf go1.18.2.linux-amd64.tar.gz
        export PATH=${TEMP_DIR}/go/bin:$PATH
    fi
    if [[ -z $(rosa version)  ]]; then
        mkdir -p ${TEMP_DIR}/bin/
        curl -L $(curl -sSL https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa_Linux_x86_64.tar.gz\") | .browser_download_url") --output ${TEMP_DIR}/bin/rosa
        curl -L $(curl -sSL https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output ${TEMP_DIR}/bin/ocm
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
        ./aws/install --install-dir "$TEMP_DIR/.aws-cli" --bin-dir "$TEMP_DIR/.aws-cli/bin" --update
        export PATH="$TEMP_DIR/.aws-cli/bin:$PATH"
    fi
    echo [default] > ${TEMP_DIR}/aws_credentials
    echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> ${TEMP_DIR}/aws_credentials
    echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> ${TEMP_DIR}/aws_credentials
    echo [default] > ${TEMP_DIR}/aws_config
    echo region=$AWS_REGION >> ${TEMP_DIR}/aws_config
    echo output=json >> ${TEMP_DIR}/aws_config
    export AWS_SHARED_CREDENTIALS_FILE=${AWS_SHARED_CREDENTIALS_FILE:-${TEMP_DIR}/aws_credentials}
    export AWS_CONFIG_FILE=${TEMP_DIR}/aws_config
}

create_egressip_external_server(){
    # Define the existing instance ID and new instance parameters
    EXISTING_WORKER_AWS_ID=$(oc --request-timeout=5s get nodes -l node-role.kubernetes.io/worker -o jsonpath --template '{range .items[*]}{.spec.providerID}{"\n"}{end}' | sed 's|.*/||' | head -n 1)
    # Retrieve the VPC ID, subnet ID, and security group IDs
    INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids $EXISTING_WORKER_AWS_ID --query "Reservations[0].Instances[0].[VpcId,SubnetId,SecurityGroups[*].GroupId]" --output json)
    VPC_ID=$(echo $INSTANCE_DETAILS | jq -r '.[0]')
    SUBNET_ID=$(echo $INSTANCE_DETAILS | jq -r '.[1]')
    SECURITY_GROUP_IDS=$(echo $INSTANCE_DETAILS | jq -r '.[2][]')
    USER_DATA_SCRIPT="user-data.sh"
    REGION="us-west-2"

    # Create the user-data script
    cat <<EOF > $USER_DATA_SCRIPT
#!/bin/bash
sudo dnf install podman -y
for port in {9002..9020}; do
    podman run --network=host -d -e LISTEN_PORT=\$port quay.io/cloud-bulldozer/nginxecho:latest
done
EOF

    # Note: We use the same name for both key and instance
    # Check and delete the key pair if exists
    # Do not exit when aws check key command has any non 0 return code
    set +e
    EXISTING_KEY=$(aws ec2 describe-key-pairs --key-names "$EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null)
    set -e
    STATUS=$?
    if [ $STATUS -eq 0 ] && [ "$EXISTING_KEY" = "$EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME" ]; then
        aws ec2 delete-key-pair --key-name "$EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME"
    fi

    # Create a new SSH key pair
    KEY_FILE="$EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME.pem"
    aws ec2 create-key-pair --key-name $EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME --query 'KeyMaterial' --output text > $KEY_FILE
    chmod 400 $KEY_FILE


    INSTANCE_TYPE="m5.xlarge"
    # Use RHEL 9 AMI ID
    IMAGE_ID="ami-0f7197c592205b389"
    EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID --count 1 --instance-type $INSTANCE_TYPE --key-name $EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME --subnet-id $SUBNET_ID --security-group-ids $SECURITY_GROUP_IDS --user-data file://$USER_DATA_SCRIPT --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME}]" --query 'Instances[0].InstanceId' --output text)
    # Wait for the instance to be in a running state
    aws ec2 wait instance-running --instance-ids $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID
    export EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID=$EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID
    sleep 60
    export EGRESSIP_EXTERNAL_SERVER_IP=$(aws ec2 describe-instances --instance-ids $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
}

cleanup_egressip_external_server(){
    # Note: We use the same name for both key and instance
    CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME="$CLUSTER_NAME-egress-server"
    INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID --query "Reservations[*].Instances[*].State.Name" --output text 2>/dev/null)
    if [ -z "$INSTANCE_STATE" ]; then
        echo "Instance ID $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID does not exist."
    else
        echo "Instance ID $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID exists with state $INSTANCE_STATE."
    
    # Terminate the instance
    aws ec2 terminate-instances --instance-ids $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID
    
    echo "Instance ID $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID is being terminated."
    aws ec2 delete-key-pair --key-name $EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME
fi
}

get_egressip_external_server(){
    CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME="$CLUSTER_NAME-egress-server"
    EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME}" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
    # Check if an instance ID was found
    if [ -z "$EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID" ]; then
        echo "No instance found with the name: ${EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME}"
        create_egressip_external_server
    else
        echo "Instance ID for ${EGRESSIP_EXTERNAL_SERVER_INSTANCE_NAME}: ${EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID}"
        export EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID=$EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID
        export EGRESSIP_EXTERNAL_SERVER_IP=$(aws ec2 describe-instances --instance-ids $EGRESSIP_EXTERNAL_SERVER_INSTANCE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    fi

    # label all worker nodes for assigning egress IPs
    for n in $(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= -o jsonpath="{.items[*].metadata.name}"); do
        oc label nodes $n k8s.ovn.org/egress-assignable=""
    done
}

