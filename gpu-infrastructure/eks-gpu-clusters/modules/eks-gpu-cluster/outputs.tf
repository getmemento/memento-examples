output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "IAM role ARN used by worker nodes"
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.main.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_iam_openid_connect_provider.main.url
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used by the cluster"
  value       = local.subnet_ids
}

output "gpu_node_groups" {
  description = "Map of GPU node group names to their configurations"
  value = {
    for name, ng in aws_eks_node_group.gpu : name => {
      node_group_name = ng.node_group_name
      status          = ng.status
      capacity_type   = ng.capacity_type
      instance_types  = ng.instance_types
      scaling_config  = ng.scaling_config
    }
  }
}

output "cpu_node_groups" {
  description = "Map of CPU node group names to their configurations"
  value = {
    for name, ng in aws_eks_node_group.cpu : name => {
      node_group_name = ng.node_group_name
      status          = ng.status
      capacity_type   = ng.capacity_type
      instance_types  = ng.instance_types
      scaling_config  = ng.scaling_config
    }
  }
}

output "kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_region.current.name}"
}
