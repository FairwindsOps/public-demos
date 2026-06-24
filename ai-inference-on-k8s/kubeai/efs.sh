#!/bin/bash
#
# Create (or repair) the EFS file system used by the KubeAI shared model cache.
#
# Required env vars:
#   CLUSTER_NAME    - EKS cluster name (e.g. catbox)
#   CLUSTER_REGION  - AWS region (e.g. us-west-2)
#
# Optional env vars:
#   EFS_NAME        - Tag/Name for the EFS file system (default: ${CLUSTER_NAME}-kai-efs)
#   EFS_SG_NAME     - Name for the EFS security group (default: kai-efs-allow-nfs-from-${CLUSTER_NAME}-nodes)
#
# This script is idempotent: re-running it will reuse existing resources rather
# than creating duplicates.

set -euo pipefail

: "${CLUSTER_NAME:?CLUSTER_NAME must be set}"
: "${CLUSTER_REGION:?CLUSTER_REGION must be set}"

EFS_NAME="${EFS_NAME:-${CLUSTER_NAME}-kai-efs}"
EFS_SG_NAME="${EFS_SG_NAME:-kai-efs-allow-nfs-from-${CLUSTER_NAME}-nodes}"

echo "==> Looking up VPC for cluster ${CLUSTER_NAME} in ${CLUSTER_REGION}"
vpc_id=$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${CLUSTER_REGION}" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)
echo "    VPC: ${vpc_id}"

# ---------------------------------------------------------------------------
# Discover the worker-node security group so the EFS SG can allow NFS from it.
# Prefer the EKS-managed cluster SG; fall back to scanning a running node.
# ---------------------------------------------------------------------------
echo "==> Discovering node security group"
node_sg_id=$(aws ec2 describe-security-groups \
    --region "${CLUSTER_REGION}" \
    --filters "Name=vpc-id,Values=${vpc_id}" \
              "Name=tag:Name,Values=${CLUSTER_NAME}-node-*" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || true)

if [[ -z "${node_sg_id}" || "${node_sg_id}" == "None" ]]; then
    # Fall back to the EKS-managed cluster security group.
    node_sg_id=$(aws eks describe-cluster \
        --name "${CLUSTER_NAME}" \
        --region "${CLUSTER_REGION}" \
        --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
        --output text)
fi

if [[ -z "${node_sg_id}" || "${node_sg_id}" == "None" ]]; then
    echo "ERROR: could not determine node security group for ${CLUSTER_NAME}" >&2
    exit 1
fi
echo "    Node SG: ${node_sg_id}"

# ---------------------------------------------------------------------------
# Create or reuse the EFS security group, and ensure it allows TCP/2049 from
# the node SG.
# ---------------------------------------------------------------------------
echo "==> Ensuring EFS security group ${EFS_SG_NAME} exists"
security_group_id=$(aws ec2 describe-security-groups \
    --region "${CLUSTER_REGION}" \
    --filters "Name=vpc-id,Values=${vpc_id}" \
              "Name=group-name,Values=${EFS_SG_NAME}" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || true)

if [[ -z "${security_group_id}" || "${security_group_id}" == "None" ]]; then
    security_group_id=$(aws ec2 create-security-group \
        --region "${CLUSTER_REGION}" \
        --group-name "${EFS_SG_NAME}" \
        --description "Allow NFS from ${CLUSTER_NAME} nodes to KubeAI EFS" \
        --vpc-id "${vpc_id}" \
        --query "GroupId" \
        --output text)
    echo "    Created SG: ${security_group_id}"
else
    echo "    Reusing SG: ${security_group_id}"
fi

echo "==> Ensuring NFS ingress (tcp/2049) from node SG ${node_sg_id}"
aws ec2 authorize-security-group-ingress \
    --region "${CLUSTER_REGION}" \
    --group-id "${security_group_id}" \
    --ip-permissions "IpProtocol=tcp,FromPort=2049,ToPort=2049,UserIdGroupPairs=[{GroupId=${node_sg_id}}]" \
    >/dev/null 2>&1 || echo "    Rule already present (ok)"

# ---------------------------------------------------------------------------
# Create or reuse the EFS file system.
# ---------------------------------------------------------------------------
echo "==> Ensuring EFS file system ${EFS_NAME} exists"
file_system_id=$(aws efs describe-file-systems \
    --region "${CLUSTER_REGION}" \
    --query "FileSystems[?Name=='${EFS_NAME}'].FileSystemId | [0]" \
    --output text 2>/dev/null || true)

if [[ -z "${file_system_id}" || "${file_system_id}" == "None" ]]; then
    file_system_id=$(aws efs create-file-system \
        --region "${CLUSTER_REGION}" \
        --performance-mode generalPurpose \
        --tags "Key=Name,Value=${EFS_NAME}" \
        --query "FileSystemId" \
        --output text)
    echo "    Created EFS: ${file_system_id}"

    # Wait for the file system to be available before adding mount targets.
    echo "    Waiting for EFS to become available..."
    while true; do
        state=$(aws efs describe-file-systems \
            --region "${CLUSTER_REGION}" \
            --file-system-id "${file_system_id}" \
            --query "FileSystems[0].LifeCycleState" \
            --output text)
        [[ "${state}" == "available" ]] && break
        sleep 3
    done
else
    echo "    Reusing EFS: ${file_system_id}"
fi

# ---------------------------------------------------------------------------
# Create or repair a mount target in every cluster subnet, with the correct SG.
# ---------------------------------------------------------------------------
echo "==> Reconciling mount targets across cluster subnets"
subnets=$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${CLUSTER_REGION}" \
    --query "cluster.resourcesVpcConfig.subnetIds[]" \
    --output text)

# Index existing mount targets by subnet for quick lookup.
existing_mts_json=$(aws efs describe-mount-targets \
    --region "${CLUSTER_REGION}" \
    --file-system-id "${file_system_id}" \
    --output json)

for subnet in ${subnets}; do
    mt_id=$(echo "${existing_mts_json}" | \
        jq -r --arg s "${subnet}" '.MountTargets[] | select(.SubnetId==$s) | .MountTargetId')

    if [[ -z "${mt_id}" ]]; then
        echo "    Creating mount target in ${subnet}"
        mt_id=$(aws efs create-mount-target \
            --region "${CLUSTER_REGION}" \
            --file-system-id "${file_system_id}" \
            --subnet-id "${subnet}" \
            --security-groups "${security_group_id}" \
            --query "MountTargetId" \
            --output text)
    else
        echo "    Mount target ${mt_id} already exists in ${subnet}; ensuring SG"
        aws efs modify-mount-target-security-groups \
            --region "${CLUSTER_REGION}" \
            --mount-target-id "${mt_id}" \
            --security-groups "${security_group_id}" >/dev/null
    fi
done

echo
echo "Done."
echo "  EFS file system ID: ${file_system_id}"
echo "  EFS security group: ${security_group_id}"
echo
echo "Update storageclass.yaml with:"
echo "  parameters.fileSystemId: \"${file_system_id}\""
