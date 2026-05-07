# Create the shared network fabric that hosts the EKS control plane, nodes, RDS, and ElastiCache.
module "vpc" {
  # Reuse the community VPC module instead of hand-building every subnet and route table resource.
  source = "terraform-aws-modules/vpc/aws"
  # Pin the module to the current major version for predictable behavior.
  version = "~> 6.0"

  # Name the VPC consistently with the rest of the stack.
  name = local.name
  # Use the CIDR block declared in locals for the whole VPC.
  cidr = local.vpc_cidr
  # Spread subnets across the availability zones chosen in locals.
  azs = local.azs

  # Carve three private application subnets from the VPC CIDR for EKS nodes and data stores.
  private_subnets = [for index, zone in local.azs : cidrsubnet(local.vpc_cidr, 4, index)]
  # Carve three public subnets from the VPC CIDR for the internet-facing load balancer.
  public_subnets = [for index, zone in local.azs : cidrsubnet(local.vpc_cidr, 8, index + 48)]
  # Carve three isolated intra subnets that Auto Mode can use for internal control-plane-adjacent traffic if needed.
  intra_subnets = [for index, zone in local.azs : cidrsubnet(local.vpc_cidr, 8, index + 52)]

  # Turn on a NAT gateway so private nodes and pods can reach the internet for image pulls and package access.
  enable_nat_gateway = true
  # Use a single NAT gateway to keep cost down in a development stack.
  single_nat_gateway = true
  # Avoid provisioning one NAT gateway per AZ because this stack is optimized for simplicity over maximum HA cost.
  one_nat_gateway_per_az = false

  # Enable DNS hostnames so internal AWS endpoints and Kubernetes workloads resolve cleanly.
  enable_dns_hostnames = true
  # Enable DNS support so the VPC resolver works for services like RDS and ElastiCache.
  enable_dns_support = true

  # Allow propagated VPN gateway routes to reach private route tables if you add hybrid networking later.
  propagate_private_route_tables_vgw = true
  # Allow propagated VPN gateway routes to reach public route tables if you add hybrid networking later.
  propagate_public_route_tables_vgw = true

  # Tag public subnets so EKS Auto Mode knows they are valid targets for internet-facing ALBs.
  public_subnet_tags = {
    # Mark the subnet as eligible for external Kubernetes load balancers.
    "kubernetes.io/role/elb" = "1"
  }

  # Tag private subnets so EKS Auto Mode knows they are valid targets for internal ALBs.
  private_subnet_tags = {
    # Mark the subnet as eligible for internal Kubernetes load balancers.
    "kubernetes.io/role/internal-elb" = "1"
  }

  # Propagate the standard tag set to all VPC resources created by the module.
  tags = local.tags
}
