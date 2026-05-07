# Build the trust policy that allows the EKS control plane service to assume the cluster IAM role.
data "aws_iam_policy_document" "cluster_assume_role" {
  # Add a single statement granting the EKS service permission to assume the role.
  statement {
    # Allow EKS Auto Mode to assume the role and attach the session tags it uses for downstream AWS operations.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    # Scope the trust relationship to the Amazon EKS service principal.
    principals {
      # Declare that the principal is an AWS service.
      type = "Service"
      # Limit assumption to the EKS service.
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# Create the IAM role used by the EKS control plane and Auto Mode control loops.
resource "aws_iam_role" "cluster" {
  # Give the role a stable name derived from the cluster name.
  name = "${local.name}-cluster-role"
  # Attach the trust policy document created above.
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  # Tag the role for easier discovery in the IAM console.
  tags = local.tags
}

# Attach the AWS-managed policies required by the EKS Auto Mode cluster role.
resource "aws_iam_role_policy_attachment" "cluster" {
  # Loop over the required policy ARNs so each one becomes a separate attachment resource.
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ])
  # Attach the current policy ARN from the loop.
  policy_arn = each.value
  # Attach each policy to the EKS cluster role.
  role = aws_iam_role.cluster.name
}

# Create the trust policy that allows EC2 instances provisioned by Auto Mode to assume the node role.
data "aws_iam_policy_document" "node_assume_role" {
  # Add a single statement granting EC2 permission to assume the role.
  statement {
    # Allow the standard role-assumption action used by EC2 instances.
    actions = ["sts:AssumeRole"]

    # Scope the trust relationship to the EC2 service principal.
    principals {
      # Declare that the principal is an AWS service.
      type = "Service"
      # Limit assumption to EC2 instances launched for the cluster.
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Create the IAM role that EKS Auto Mode assigns to worker nodes it provisions for the cluster.
resource "aws_iam_role" "node" {
  # Give the role a stable name derived from the cluster name.
  name = "${local.name}-node-role"
  # Attach the EC2 trust policy document created above.
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  # Tag the role for easier discovery in the IAM console.
  tags = local.tags
}

# Attach the AWS-managed policies required by EKS Auto Mode nodes.
resource "aws_iam_role_policy_attachment" "node" {
  # Loop over the required policy ARNs so each one becomes a separate attachment resource.
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  # Attach the current policy ARN from the loop.
  policy_arn = each.value
  # Attach each policy to the EKS node role.
  role = aws_iam_role.node.name
}
