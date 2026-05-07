# Accept the local AWS profile name so the stack can run under different workstations without editing code.
variable "aws_profile" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Local AWS CLI profile used by the AWS provider."
  # Enforce that the value is plain text.
  type = string
  # Default to the profile already used in the repository before this rewrite.
  default = "Saar"
}

# Accept the database username that will be reused by both RDS instances and injected into both services.
variable "db_username" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "PostgreSQL username used by both application databases."
  # Enforce that the value is plain text.
  type = string
  # Mark the value as sensitive so Terraform hides it in normal CLI output.
  sensitive = true
}

# Accept an optional existing Secrets Manager ARN for the shared JWT signing key.
variable "existing_access_token_secret_arn" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Optional existing Secrets Manager ARN that stores a JSON field named access_token."
  # Enforce that the value is plain text.
  type = string
  # Default to an empty string so Terraform creates the secret when the caller doesn't supply one.
  default = ""
}

# Accept the DNS host name that the ALB ingress rules should match.
variable "domain_name" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Public host name routed by the ALB ingress."
  # Enforce that the value is plain text.
  type = string
  # Preserve the hostname already hardcoded in the chart before the rewrite.
  default = "saarskittel.com"
}

# Accept the scheme for the ALB so the same stack can build a public or internal ingress entry point.
variable "alb_scheme" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "ALB exposure mode used by the EKS Auto Mode ingress class."
  # Enforce that the value is plain text.
  type = string
  # Default to a public ALB because the services are intended to be reachable by host name.
  default = "internet-facing"
}

# Accept optional certificate ARNs so HTTPS can be added without changing Terraform code again.
variable "certificate_arns" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Optional ACM certificate ARNs attached to the ALB ingress class."
  # Enforce that the value is a list of strings.
  type = list(string)
  # Default to an empty list so HTTP works without additional ACM setup.
  default = []
}

# Accept an optional IAM principal ARN for explicit cluster-admin access entries.
variable "cluster_admin_principal_arn" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Optional IAM principal ARN to receive an explicit EKS cluster-admin access entry."
  # Enforce that the value is plain text.
  type = string
  # Default to an empty string so the access entry resources stay disabled unless requested.
  default = ""
}

# Allow the stack to create an explicit EKS access entry in addition to cluster creator bootstrap access.
variable "enable_cluster_admin_access_entry" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Whether to create an explicit EKS access entry for cluster_admin_principal_arn."
  # Enforce that the value is boolean.
  type = bool
  # Default to false because bootstrap creator admin access is enabled automatically.
  default = false
}

# Accept the Helm release name so the chart can be installed under a predictable identifier.
variable "release_name" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Helm release name used for the messaging-system chart."
  # Enforce that the value is plain text.
  type = string
  # Default to the existing chart name for familiarity.
  default = "messaging-system"
}

# Accept the authentication service image so the app can be upgraded without editing the chart.
variable "auth_image" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Container image used by the authentication service."
  # Enforce that the value is plain text.
  type = string
  # Preserve the image already used by the chart before the rewrite.
  default = "saarskittel/authentication-k8s"
}

# Accept the messaging service image so the app can be upgraded without editing the chart.
variable "messaging_image" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Container image used by the messaging service."
  # Enforce that the value is plain text.
  type = string
  # Preserve the image already used by the chart before the rewrite.
  default = "saarskittel/messaging-k8s"
}

# Accept a simple environment label so tags and documentation can distinguish dev from future stages.
variable "environment" {
  # Explain what the variable controls when Terraform prompts for input.
  description = "Environment label applied to resource tags."
  # Enforce that the value is plain text.
  type = string
  # Default to development because this repository is currently a single-environment stack.
  default = "development"
}
