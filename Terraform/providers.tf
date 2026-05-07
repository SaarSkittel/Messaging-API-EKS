# Require recent Terraform and provider versions so the EKS Auto Mode resources below behave consistently.
terraform {
  # Pin the minimum Terraform CLI version expected by this stack.
  required_version = ">= 1.5.0"

  # Declare every provider used by the root module.
  required_providers {
    # The AWS provider creates all cloud infrastructure resources.
    aws = {
      # Pull the provider from the official HashiCorp registry namespace.
      source = "hashicorp/aws"
      # Stay on the current major version while allowing compatible updates.
      version = "~> 6.31"
    }

    # The Kubernetes provider creates cluster-scoped objects after EKS is ready.
    kubernetes = {
      # Pull the provider from the official HashiCorp registry namespace.
      source = "hashicorp/kubernetes"
      # Stay on the current major version while allowing compatible updates.
      version = "~> 2.31"
    }

    # The Helm provider installs the application chart into the EKS cluster.
    helm = {
      # Pull the provider from the official HashiCorp registry namespace.
      source = "hashicorp/helm"
      # Stay on the current major version while allowing compatible updates.
      version = "~> 2.14"
    }

    # The Random provider generates bootstrap secrets when the caller doesn't supply a pre-created secret.
    random = {
      # Pull the provider from the official HashiCorp registry namespace.
      source = "hashicorp/random"
      # Stay on the current major version while allowing compatible updates.
      version = "~> 3.6"
    }
  }
}

# Configure the AWS provider that creates the VPC, EKS cluster, RDS, and ElastiCache resources.
provider "aws" {
  # Deploy everything into the AWS region declared in locals.
  region = local.region
  # Use the named local AWS CLI profile so Terraform matches your workstation credentials.
  profile = var.aws_profile
}

# Read details about the caller so the stack can expose who created the environment.
data "aws_caller_identity" "current" {}

# Read the created EKS cluster back from AWS after the control plane exists.
data "aws_eks_cluster" "cluster" {
  # Look up the cluster by the name created in eks.tf.
  name = aws_eks_cluster.cluster.name
  # Force this lookup to wait until the cluster resource has been created.
  depends_on = [aws_eks_cluster.cluster]
}

# Request a temporary authentication token that Terraform can use against the Kubernetes API.
data "aws_eks_cluster_auth" "cluster" {
  # Generate the token for the same cluster read above.
  name = aws_eks_cluster.cluster.name
  # Force token generation to wait until the cluster resource has been created.
  depends_on = [aws_eks_cluster.cluster]
}

# Configure the Kubernetes provider so Terraform can create manifests inside the new cluster.
provider "kubernetes" {
  # Point the provider at the HTTPS endpoint exposed by the EKS control plane.
  host = data.aws_eks_cluster.cluster.endpoint
  # Decode the base64 certificate authority bundle returned by EKS.
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  # Authenticate to Kubernetes using the short-lived token from the AWS API.
  token = data.aws_eks_cluster_auth.cluster.token
}

# Configure the Helm provider to use the same Kubernetes connection details as the Kubernetes provider.
provider "helm" {
  # Nest a Kubernetes connection block because Helm installs releases through the Kubernetes API.
  kubernetes {
    # Point Helm at the same EKS API server endpoint.
    host = data.aws_eks_cluster.cluster.endpoint
    # Decode the same EKS certificate authority bundle for TLS verification.
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    # Reuse the same short-lived token generated for Kubernetes access.
    token = data.aws_eks_cluster_auth.cluster.token
  }
}
