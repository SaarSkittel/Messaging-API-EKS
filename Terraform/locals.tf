# Query the availability zones in the selected region so the VPC can span multiple zones automatically.
data "aws_availability_zones" "available" {
  # Filter out opt-in local zones to keep the subnet math simple and broadly available.
  filter {
    # Filter on the zone opt-in status attribute exposed by AWS.
    name = "opt-in-status"
    # Keep only zones that are available without additional account enrollment.
    values = ["opt-in-not-required"]
  }
}

# Collect all reusable constants in one place so the rest of the stack stays readable.
locals {
  # Name the EKS cluster and the broader stack consistently across resources.
  name = "messaging-api-cluster"
  # Target the same AWS region that was already used in the original configuration.
  region = "us-east-1"
  # Keep the Kubernetes version explicit instead of inheriting whatever EKS chooses by default.
  kubernetes_version = "1.34"

  # Define the VPC CIDR block that all subnets are carved from.
  vpc_cidr = "10.0.0.0/16"
  # Use the first three standard availability zones in the region for high availability.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Keep the authentication namespace name in one place for reuse by Terraform and Helm values.
  auth_namespace = "authentication"
  # Keep the messaging namespace name in one place for reuse by Terraform and Helm values.
  messaging_namespace = "messaging"
  # Keep the ingress class name in one place for reuse by Terraform and Helm values.
  alb_ingress_class_name = "alb"
  # Group both namespace-specific ingress objects behind a single ALB.
  alb_group_name = local.name
  # Use a stable service account name for the authentication workloads that need Secrets Manager access.
  auth_service_account_name = "auth-workload"
  # Use a stable service account name for the messaging workloads that need Secrets Manager access.
  messaging_service_account_name = "messaging-workload"
  # Use a stable SecretProviderClass name for the authentication namespace.
  auth_secret_provider_class_name = "auth-aws-secrets"
  # Use a stable SecretProviderClass name for the messaging namespace.
  messaging_secret_provider_class_name = "messaging-aws-secrets"
  # Use a stable secret name when Terraform creates the shared JWT signing secret.
  access_token_secret_name = "messaging-api-shared-access-token"

  # Standardize the PostgreSQL port used by the application containers and RDS instances.
  postgres_port = 5432
  # Standardize the Redis port used by the application containers and ElastiCache clusters.
  redis_port = 6379

  # Match the current Django settings that still default to the postgres database name.
  auth_database_name = "postgres"
  # Match the current Django settings that still default to the postgres database name.
  messaging_database_name = "postgres"

  # Use the caller-supplied access token secret ARN when present, otherwise fall back to the secret created by Terraform.
  access_token_secret_arn = var.existing_access_token_secret_arn != "" ? var.existing_access_token_secret_arn : aws_secretsmanager_secret.access_token[0].arn

  # Select the appropriate subnet tag set for ALB placement based on the desired exposure scheme.
  alb_subnet_match_tags = var.alb_scheme == "internal" ? { "kubernetes.io/role/internal-elb" = "1" } : { "kubernetes.io/role/elb" = "1" }

  # Apply a common tag set to every AWS resource to make the environment easier to browse and cost-track.
  tags = {
    # Tag each resource with the logical project name.
    Name = local.name
    # Tag each resource with the environment label supplied by the caller.
    Environment = var.environment
    # Tag each resource so it is obvious that Terraform manages it.
    Terraform = "true"
    # Tag each resource with the repository project name for easier discovery in the AWS console.
    Project = "Messaging-API-EKS"
  }
}
