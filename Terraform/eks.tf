# Create the Amazon EKS cluster that runs the application platform.
resource "aws_eks_cluster" "cluster" {
  # Name the cluster using the shared local value.
  name = local.name
  # Attach the IAM role created for the EKS control plane.
  role_arn = aws_iam_role.cluster.arn
  # Pin the Kubernetes version so upgrades are intentional.
  version = local.kubernetes_version

  # Disable legacy self-managed addon bootstrapping because Auto Mode handles cluster capabilities directly.
  bootstrap_self_managed_addons = false

  # Place the cluster into the private application subnets created by the VPC module.
  vpc_config {
    # Allow EKS to use the private subnets for nodes and networking.
    subnet_ids = module.vpc.private_subnets
    # Keep the private cluster endpoint enabled for in-VPC access.
    endpoint_private_access = true
    # Keep the public cluster endpoint enabled so local administration still works from your workstation.
    endpoint_public_access = true
  }

  # Use API-based authentication so the cluster supports modern EKS access entries.
  access_config {
    # Turn on the EKS API authentication mode recommended for Auto Mode.
    authentication_mode = "API"
    # Grant the cluster creator initial admin rights so the first Helm and Kubernetes operations can succeed.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Enable Auto Mode compute so EKS can provision and scale worker nodes automatically.
  compute_config {
    # Turn on the Auto Mode compute capability.
    enabled = true
    # Supply the IAM role that Auto Mode should attach to the managed EC2 instances it creates.
    node_role_arn = aws_iam_role.node.arn
    # Ask Auto Mode to create the default system and general-purpose node pools.
    node_pools = ["system", "general-purpose"]
  }

  # Enable the Auto Mode load balancing capability so ALBs are created from Kubernetes ingress resources.
  kubernetes_network_config {
    # Turn on the managed Elastic Load Balancing integration.
    elastic_load_balancing {
      # Enable EKS Auto Mode ALB management.
      enabled = true
    }
  }

  # Enable the Auto Mode block storage capability so workloads can use EBS-backed PVCs if needed later.
  storage_config {
    # Turn on the managed block storage integration.
    block_storage {
      # Enable EKS Auto Mode EBS management.
      enabled = true
    }
  }

  # Tag the cluster for easier discovery in the AWS console.
  tags = local.tags

  # Wait for the required IAM policy attachments before creating the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy_attachment.node,
  ]
}

# Optionally create an explicit access entry for a second IAM principal that should administer the cluster.
resource "aws_eks_access_entry" "cluster_admin" {
  # Create this resource only when the caller has enabled explicit access-entry management.
  count = var.enable_cluster_admin_access_entry ? 1 : 0
  # Target the cluster created above.
  cluster_name = aws_eks_cluster.cluster.name
  # Grant access to the IAM principal passed in through variables.
  principal_arn = var.cluster_admin_principal_arn
  # Create a standard human-or-automation access entry.
  type = "STANDARD"
}

# Associate the cluster-admin access policy with the optional access entry above.
resource "aws_eks_access_policy_association" "cluster_admin" {
  # Create this resource only when the caller has enabled explicit access-entry management.
  count = var.enable_cluster_admin_access_entry ? 1 : 0
  # Target the cluster created above.
  cluster_name = aws_eks_cluster.cluster.name
  # Reuse the same IAM principal ARN used by the access entry.
  principal_arn = var.cluster_admin_principal_arn
  # Attach the AWS-managed cluster-admin access policy.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  # Apply the policy across the whole cluster instead of a limited namespace set.
  access_scope {
    # Grant cluster-wide scope.
    type = "cluster"
  }

  # Wait until the corresponding access entry exists before attaching the access policy.
  depends_on = [aws_eks_access_entry.cluster_admin]
}
