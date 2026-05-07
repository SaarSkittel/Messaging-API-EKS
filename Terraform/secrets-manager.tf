# Generate a stable JWT signing key only when the caller didn't supply an existing Secrets Manager secret ARN.
resource "random_password" "access_token" {
  # Create this bootstrap value only when Terraform is responsible for creating the secret.
  count = var.existing_access_token_secret_arn == "" ? 1 : 0
  # Use a long random value that works well as an HMAC signing secret.
  length = 64
  # Avoid special characters so the value is easy to consume from shells and application env vars.
  special = false
}

# Create a shared Secrets Manager secret for the JWT signing key only when the caller didn't supply one.
resource "aws_secretsmanager_secret" "access_token" {
  # Create this secret only when Terraform is responsible for it.
  count = var.existing_access_token_secret_arn == "" ? 1 : 0
  # Give the secret a stable human-readable name.
  name = local.access_token_secret_name
  # Keep the default short recovery window so accidental deletes can be recovered in development.
  recovery_window_in_days = 7
  # Apply the shared tag set to the secret metadata.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = local.access_token_secret_name
  })
}

# Store the generated JWT signing key in Secrets Manager only when Terraform created the secret metadata above.
resource "aws_secretsmanager_secret_version" "access_token" {
  # Create this secret version only when Terraform is responsible for it.
  count = var.existing_access_token_secret_arn == "" ? 1 : 0
  # Point the version at the secret metadata resource created above.
  secret_id = aws_secretsmanager_secret.access_token[0].id
  # Store the value as JSON so the SecretProviderClass can mount the access_token field by name.
  secret_string = jsonencode({
    # Persist the generated JWT signing key under a descriptive field name.
    access_token = random_password.access_token[0].result
  })
}

# Create the EKS add-on that installs the AWS Secrets and Configuration Provider and its CSI dependency.
resource "aws_eks_addon" "secrets_store_csi_provider" {
  # Install the add-on into the current cluster.
  cluster_name = aws_eks_cluster.cluster.name
  # Use the official EKS add-on name published by AWS.
  addon_name = "aws-secrets-store-csi-driver-provider"
  # Preserve any cluster-managed settings on later updates.
  resolve_conflicts_on_update = "PRESERVE"
  # Tag the add-on for easier discovery in the AWS console.
  tags = local.tags
}

# Build the trust policy that allows EKS Pod Identity to assume the authentication workload role.
data "aws_iam_policy_document" "auth_pod_identity_assume_role" {
  # Add a single statement granting EKS Pod Identity permission to assume the role.
  statement {
    # Allow the standard pod-identity role-assumption actions.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    # Scope the trust relationship to the EKS Pod Identity service principal.
    principals {
      # Declare that the principal is an AWS service.
      type = "Service"
      # Limit assumption to the Pod Identity service.
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Create the IAM role used by authentication pods when they fetch secrets from Secrets Manager.
resource "aws_iam_role" "auth_pod_identity" {
  # Give the role a stable name derived from the cluster name.
  name = "${local.name}-auth-pod-identity-role"
  # Attach the Pod Identity trust policy created above.
  assume_role_policy = data.aws_iam_policy_document.auth_pod_identity_assume_role.json
  # Apply the shared tag set to the role.
  tags = local.tags
}

# Build the least-privilege policy that lets authentication pods read only the secrets they need.
data "aws_iam_policy_document" "auth_pod_identity" {
  # Allow the pod to read the shared JWT signing secret and its own RDS-managed credential secret.
  statement {
    # Grant only the read operations required by the CSI provider.
    actions = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    # Scope access to the shared access-token secret and the authentication database secret.
    resources = [local.access_token_secret_arn, aws_db_instance.auth.master_user_secret[0].secret_arn]
  }
}

# Attach the least-privilege secrets policy to the authentication pod identity role.
resource "aws_iam_role_policy" "auth_pod_identity" {
  # Give the inline policy a stable name.
  name = "${local.name}-auth-secrets-policy"
  # Attach the policy to the authentication pod identity role.
  role = aws_iam_role.auth_pod_identity.id
  # Use the JSON policy document created above.
  policy = data.aws_iam_policy_document.auth_pod_identity.json
}

# Associate the authentication service account with the IAM role above using EKS Pod Identity.
resource "aws_eks_pod_identity_association" "auth" {
  # Target the current EKS cluster.
  cluster_name = aws_eks_cluster.cluster.name
  # Scope the association to the authentication namespace.
  namespace = local.auth_namespace
  # Match the service account name that the Helm chart assigns to the pods.
  service_account = local.auth_service_account_name
  # Grant that service account the authentication pod identity role.
  role_arn = aws_iam_role.auth_pod_identity.arn
}

# Build the trust policy that allows EKS Pod Identity to assume the messaging workload role.
data "aws_iam_policy_document" "messaging_pod_identity_assume_role" {
  # Add a single statement granting EKS Pod Identity permission to assume the role.
  statement {
    # Allow the standard pod-identity role-assumption actions.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    # Scope the trust relationship to the EKS Pod Identity service principal.
    principals {
      # Declare that the principal is an AWS service.
      type = "Service"
      # Limit assumption to the Pod Identity service.
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Create the IAM role used by messaging pods when they fetch secrets from Secrets Manager.
resource "aws_iam_role" "messaging_pod_identity" {
  # Give the role a stable name derived from the cluster name.
  name = "${local.name}-messaging-pod-identity-role"
  # Attach the Pod Identity trust policy created above.
  assume_role_policy = data.aws_iam_policy_document.messaging_pod_identity_assume_role.json
  # Apply the shared tag set to the role.
  tags = local.tags
}

# Build the least-privilege policy that lets messaging pods read only the secrets they need.
data "aws_iam_policy_document" "messaging_pod_identity" {
  # Allow the pod to read the shared JWT signing secret and its own RDS-managed credential secret.
  statement {
    # Grant only the read operations required by the CSI provider.
    actions = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    # Scope access to the shared access-token secret and the messaging database secret.
    resources = [local.access_token_secret_arn, aws_db_instance.messaging.master_user_secret[0].secret_arn]
  }
}

# Attach the least-privilege secrets policy to the messaging pod identity role.
resource "aws_iam_role_policy" "messaging_pod_identity" {
  # Give the inline policy a stable name.
  name = "${local.name}-messaging-secrets-policy"
  # Attach the policy to the messaging pod identity role.
  role = aws_iam_role.messaging_pod_identity.id
  # Use the JSON policy document created above.
  policy = data.aws_iam_policy_document.messaging_pod_identity.json
}

# Associate the messaging service account with the IAM role above using EKS Pod Identity.
resource "aws_eks_pod_identity_association" "messaging" {
  # Target the current EKS cluster.
  cluster_name = aws_eks_cluster.cluster.name
  # Scope the association to the messaging namespace.
  namespace = local.messaging_namespace
  # Match the service account name that the Helm chart assigns to the pods.
  service_account = local.messaging_service_account_name
  # Grant that service account the messaging pod identity role.
  role_arn = aws_iam_role.messaging_pod_identity.arn
}
