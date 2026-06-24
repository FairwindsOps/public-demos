#!/bin/bash

vpc_id=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

cidr_range=$(aws ec2 describe-vpcs \
    --vpc-ids $vpc_id \
    --query "Vpcs[].CidrBlock" \
    --output text \
    --region ${CLUSTER_REGION})

security_group_id=$(aws ec2 create-security-group \
    --group-name MyEfsSecurityGroup \
    --description "My EFS security group" \
    --vpc-id $vpc_id \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $cidr_range

file_system_id=$(aws efs create-file-system \
    --region ${CLUSTER_REGION} \
    --performance-mode generalPurpose \
    --query 'FileSystemId' \
    --output text)

SUBNETS=$(eksctl get cluster --region us-west-2 catbox -o json | jq -r '.[0].ResourcesVpcConfig.SubnetIds[]')

while IFS= read -r subnet; do
    echo "Creating EFS mount target in $subnet"
    aws efs create-mount-target --file-system-id fs-0b81a416d90e7585c \
      --subnet-id $subnet --security-groups $security_group_id --output text
done <<< "$SUBNETS"
