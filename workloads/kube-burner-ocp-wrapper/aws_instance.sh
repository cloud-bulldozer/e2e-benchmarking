#!/usr/bin/env bash
set -x

export AWS_REGION=${AWS_REGION:-us-west-2}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}

TEMP_DIR=`mktemp -d`

install_oc_cli(){
    if [[ -z $(go version) ]]; then
        dnf install golang -y
    fi
    if [[ -z $(oc version) ]]; then
	curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz | tar -xvzf -
        mv oc kubectl ${TEMP_DIR}/bin/
    fi
}

configure_aws(){
    if [[ -z $(aws --version) ]]; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install --install-dir "$TEMP_DIR/.aws-cli" --bin-dir "$TEMP_DIR/.aws-cli/bin" --update
        export PATH="$TEMP_DIR/.aws-cli/bin:$PATH"
    fi
	if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
		export AWS_SHARED_CREDENTIALS_FILE="${CLUSTER_PROFILE_DIR}/.awscred"
		if [[ ! -f $AWS_SHARED_CREDENTIALS_FILE ]]; then
			echo "ERROR: AWS credentials file ${AWS_SHARED_CREDENTIALS_FILE} does not exist."
			exit 1
		fi
	else
        echo [default] > ${TEMP_DIR}/aws_credentials
        echo aws_access_key_id=$AWS_ACCESS_KEY_ID >> ${TEMP_DIR}/aws_credentials
        echo aws_secret_access_key=$AWS_SECRET_ACCESS_KEY >> ${TEMP_DIR}/aws_credentials
        echo [default] > ${TEMP_DIR}/aws_config
        echo region=$AWS_REGION >> ${TEMP_DIR}/aws_config
        echo output=json >> ${TEMP_DIR}/aws_config
        export AWS_SHARED_CREDENTIALS_FILE=${AWS_SHARED_CREDENTIALS_FILE:-${TEMP_DIR}/aws_credentials}
        export AWS_CONFIG_FILE=${TEMP_DIR}/aws_config
	fi
}

create_aws_instance(){
    # Use the worker node's subnet and security group for the new aws instance
    EXISTING_WORKER_AWS_ID=$(oc --request-timeout=5s get nodes -l node-role.kubernetes.io/worker -o jsonpath --template '{range .items[*]}{.spec.providerID}{"\n"}{end}' | sed 's|.*/||' | head -n 1)
    INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids $EXISTING_WORKER_AWS_ID --query "Reservations[0].Instances[0].[VpcId,SubnetId,SecurityGroups[*].GroupId]" --output json)
    SUBNET_ID=$(echo $INSTANCE_DETAILS | jq -r '.[1]')
	# Node security group is sufficient
    for sg_id in $(echo $INSTANCE_DETAILS | jq -r '.[2][]'); do
        name=$(aws ec2 describe-security-groups --group-ids "$sg_id" --query 'SecurityGroups[0].GroupName' --output text)
        if [[ "$name" == *-node ]]; then
		    SECURITY_GROUP_ID=$sg_id
            break
        fi
    done
	# Allow provided TCP ports
	for port in $TCP_PORTS; do
		aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port $port --source-group $SECURITY_GROUP_ID
	done
    REGION="us-west-2"

    # Note: We use the same name for both key and instance
    # Check and delete the key pair if exists
    # Do not exit when aws check key command has any non 0 return code
    set +e
    EXISTING_KEY=$(aws ec2 describe-key-pairs --key-names "$AWS_INSTANCE_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null)
    set -e
    STATUS=$?
    if [ $STATUS -eq 0 ] && [ "$EXISTING_KEY" = "$AWS_INSTANCE_NAME" ]; then
        aws ec2 delete-key-pair --key-name "$AWS_INSTANCE_NAME"
    fi

    # Create a new SSH key pair
    KEY_FILE="$AWS_INSTANCE_NAME.pem"
    aws ec2 create-key-pair --key-name $AWS_INSTANCE_NAME --query 'KeyMaterial' --output text > $KEY_FILE
    chmod 400 $KEY_FILE


    INSTANCE_TYPE="m5.xlarge"
    # Use RHEL 9 AMI ID
    IMAGE_ID="ami-0f7197c592205b389"
    AWS_INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID --count 1 --instance-type $INSTANCE_TYPE --key-name $AWS_INSTANCE_NAME --subnet-id $SUBNET_ID --security-group-ids $SECURITY_GROUP_ID --user-data file://$USER_DATA_SCRIPT --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$AWS_INSTANCE_NAME}]" --query 'Instances[0].InstanceId' --output text)
    # Wait for the instance to be in a running state
    aws ec2 wait instance-running --instance-ids $AWS_INSTANCE_ID
    export AWS_INSTANCE_ID=$AWS_INSTANCE_ID
    sleep 60
    export AWS_INSTANCE_IP=$(aws ec2 describe-instances --instance-ids $AWS_INSTANCE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
}

cleanup_aws_instance(){
    # Note: We use the same name for both key and instance
    CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export AWS_INSTANCE_NAME="$CLUSTER_NAME-aws-instance"
    INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $AWS_INSTANCE_ID --query "Reservations[*].Instances[*].State.Name" --output text 2>/dev/null)
    if [ -z "$INSTANCE_STATE" ]; then
        echo "Instance ID $AWS_INSTANCE_ID does not exist."
    else
        echo "Instance ID $AWS_INSTANCE_ID exists with state $INSTANCE_STATE."
    
    	# Terminate the instance
	    aws ec2 terminate-instances --instance-ids $AWS_INSTANCE_ID
    
    	echo "Instance ID $AWS_INSTANCE_ID is being terminated."
	    aws ec2 delete-key-pair --key-name $AWS_INSTANCE_NAME
    fi
}

get_aws_instance(){
    CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    export AWS_INSTANCE_NAME="$CLUSTER_NAME-aws-instance"
    AWS_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${AWS_INSTANCE_NAME}" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
    # Check if an instance ID was found
    if [ -z "$AWS_INSTANCE_ID" ]; then
        echo "No instance found with the name: ${AWS_INSTANCE_NAME}"
        create_aws_instance
    else
        echo "Instance ID for ${AWS_INSTANCE_NAME}: ${AWS_INSTANCE_ID}"
        export AWS_INSTANCE_ID=$AWS_INSTANCE_ID
        export AWS_INSTANCE_IP=$(aws ec2 describe-instances --instance-ids $AWS_INSTANCE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    fi
}

