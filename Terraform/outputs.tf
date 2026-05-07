# Expose the AWS account ID used for the deployment so the environment is easier to identify.
output "aws_account_id" {
  # Describe the output in Terraform UI and state.
  description = "AWS account ID used for the deployment."
  # Return the account ID discovered from the current caller identity.
  value = data.aws_caller_identity.current.account_id
}

# Expose the EKS cluster name for kubeconfig and console navigation.
output "cluster_name" {
  # Describe the output in Terraform UI and state.
  description = "Name of the EKS cluster."
  # Return the EKS cluster name.
  value = aws_eks_cluster.cluster.name
}

# Expose the EKS cluster endpoint for debugging and kubeconfig verification.
output "cluster_endpoint" {
  # Describe the output in Terraform UI and state.
  description = "HTTPS endpoint of the EKS control plane."
  # Return the EKS cluster endpoint.
  value = aws_eks_cluster.cluster.endpoint
}

# Expose the VPC ID so the networking layer is easy to cross-reference in the AWS console.
output "vpc_id" {
  # Describe the output in Terraform UI and state.
  description = "ID of the VPC created for the stack."
  # Return the VPC ID created by the module.
  value = module.vpc.vpc_id
}

# Expose the authentication database endpoint for debugging and manual connectivity checks.
output "auth_db_host" {
  # Describe the output in Terraform UI and state.
  description = "Hostname of the authentication PostgreSQL instance."
  # Return the RDS address without the port suffix.
  value = aws_db_instance.auth.address
}

# Expose the authentication database secret ARN so the Secrets Manager wiring is easy to inspect.
output "auth_db_secret_arn" {
  # Describe the output in Terraform UI and state.
  description = "Secrets Manager ARN for the authentication database credentials managed by RDS."
  # Return the RDS-managed master user secret ARN.
  value = aws_db_instance.auth.master_user_secret[0].secret_arn
}

# Expose the messaging database endpoint for debugging and manual connectivity checks.
output "messaging_db_host" {
  # Describe the output in Terraform UI and state.
  description = "Hostname of the messaging PostgreSQL instance."
  # Return the RDS address without the port suffix.
  value = aws_db_instance.messaging.address
}

# Expose the messaging database secret ARN so the Secrets Manager wiring is easy to inspect.
output "messaging_db_secret_arn" {
  # Describe the output in Terraform UI and state.
  description = "Secrets Manager ARN for the messaging database credentials managed by RDS."
  # Return the RDS-managed master user secret ARN.
  value = aws_db_instance.messaging.master_user_secret[0].secret_arn
}

# Expose the authentication Redis endpoint for debugging and manual connectivity checks.
output "auth_redis_host" {
  # Describe the output in Terraform UI and state.
  description = "Primary endpoint address of the authentication Redis cluster."
  # Return the Redis primary endpoint address.
  value = aws_elasticache_replication_group.auth.primary_endpoint_address
}

# Expose the messaging Redis endpoint for debugging and manual connectivity checks.
output "messaging_redis_host" {
  # Describe the output in Terraform UI and state.
  description = "Primary endpoint address of the messaging Redis cluster."
  # Return the Redis primary endpoint address.
  value = aws_elasticache_replication_group.messaging.primary_endpoint_address
}

# Expose the ingress class name so the Kubernetes entry point is easy to verify.
output "ingress_class_name" {
  # Describe the output in Terraform UI and state.
  description = "Name of the EKS Auto Mode ingress class used by the workloads."
  # Return the ingress class name from locals.
  value = local.alb_ingress_class_name
}

# Expose the shared JWT secret ARN so workloads and operators can reference the same secret path.
output "access_token_secret_arn" {
  # Describe the output in Terraform UI and state.
  description = "Secrets Manager ARN for the shared JWT signing key."
  # Return either the caller-supplied ARN or the secret created by Terraform.
  value = local.access_token_secret_arn
}
