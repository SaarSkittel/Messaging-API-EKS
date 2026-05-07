# Create the security group that allows application traffic from inside the VPC to reach Redis.
resource "aws_security_group" "redis" {
  # Give the security group a stable name derived from the cluster name.
  name = "${local.name}-redis-sg"
  # Describe the purpose of the security group in the AWS console.
  description = "Allow Redis traffic from workloads inside the VPC."
  # Attach the security group to the shared VPC created earlier.
  vpc_id = module.vpc.vpc_id

  # Allow Redis traffic from any source inside the VPC CIDR.
  ingress {
    # Describe the ingress rule in the AWS console.
    description = "Redis from the VPC."
    # Open the standard Redis port.
    from_port = local.redis_port
    # Close the rule at the same Redis port.
    to_port = local.redis_port
    # Restrict the rule to TCP traffic.
    protocol = "tcp"
    # Allow the full VPC CIDR so Auto Mode-managed nodes can always connect.
    cidr_blocks = [local.vpc_cidr]
  }

  # Allow all outbound traffic so the Redis nodes can reach AWS-managed dependencies if needed.
  egress {
    # Start the egress range at port zero.
    from_port = 0
    # End the egress range at port zero because protocol -1 ignores port numbers.
    to_port = 0
    # Allow every protocol.
    protocol = "-1"
    # Permit egress to all IPv4 destinations.
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Apply the shared tag set to the security group.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-redis-sg"
  })
}

# Group the private subnets into a subnet group that ElastiCache can place Redis nodes into.
resource "aws_elasticache_subnet_group" "this" {
  # Give the subnet group a stable name derived from the cluster name.
  name = "${local.name}-redis-subnet-group"
  # Use the private subnets so Redis never receives public IP addresses.
  subnet_ids = module.vpc.private_subnets
  # Describe the purpose of the subnet group in the AWS console.
  description = "Private subnets for Messaging API Redis clusters."
}

# Create the Redis replication group used by the authentication service.
resource "aws_elasticache_replication_group" "auth" {
  # Give the replication group a stable identifier derived from the cluster name.
  replication_group_id = "${local.name}-auth-redis"
  # Describe the purpose of the Redis cluster in the AWS console.
  description = "Redis cache for the authentication service."
  # Use Redis as the cache engine.
  engine = "redis"
  # Pin the Redis major version to a current release.
  engine_version = "7.1"
  # Choose a small node size suitable for a development environment.
  node_type = "cache.t4g.micro"
  # Keep a single cache node for lower cost in development.
  num_cache_clusters = 1
  # Expose the standard Redis port.
  port = local.redis_port

  # Place the cluster into the private subnet group created above.
  subnet_group_name = aws_elasticache_subnet_group.this.name
  # Attach the Redis security group created above.
  security_group_ids = [aws_security_group.redis.id]
  # Use the default Redis 7 parameter group.
  parameter_group_name = "default.redis7"

  # Disable automatic failover because there is only one node in this development stack.
  automatic_failover_enabled = false
  # Encrypt the cache data at rest.
  at_rest_encryption_enabled = true
  # Encrypt client and node traffic in transit so Redis is not exposed in plain text.
  transit_encryption_enabled = true
  # Apply changes immediately during development iterations.
  apply_immediately = true

  # Retain a short history of automatic snapshots.
  snapshot_retention_limit = 1
  # Choose a predictable snapshot window.
  snapshot_window = "03:00-05:00"

  # Apply the shared tag set to the Redis cluster.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-auth-redis"
    # Tag the cluster with the service that uses it.
    Service = "authentication"
  })
}

# Create the Redis replication group used by the messaging service.
resource "aws_elasticache_replication_group" "messaging" {
  # Give the replication group a stable identifier derived from the cluster name.
  replication_group_id = "${local.name}-messaging-redis"
  # Describe the purpose of the Redis cluster in the AWS console.
  description = "Redis cache for the messaging service."
  # Use Redis as the cache engine.
  engine = "redis"
  # Pin the Redis major version to a current release.
  engine_version = "7.1"
  # Choose a small node size suitable for a development environment.
  node_type = "cache.t4g.micro"
  # Keep a single cache node for lower cost in development.
  num_cache_clusters = 1
  # Expose the standard Redis port.
  port = local.redis_port

  # Place the cluster into the private subnet group created above.
  subnet_group_name = aws_elasticache_subnet_group.this.name
  # Attach the Redis security group created above.
  security_group_ids = [aws_security_group.redis.id]
  # Use the default Redis 7 parameter group.
  parameter_group_name = "default.redis7"

  # Disable automatic failover because there is only one node in this development stack.
  automatic_failover_enabled = false
  # Encrypt the cache data at rest.
  at_rest_encryption_enabled = true
  # Encrypt client and node traffic in transit so Redis is not exposed in plain text.
  transit_encryption_enabled = true
  # Apply changes immediately during development iterations.
  apply_immediately = true

  # Retain a short history of automatic snapshots.
  snapshot_retention_limit = 1
  # Choose a predictable snapshot window.
  snapshot_window = "03:00-05:00"

  # Apply the shared tag set to the Redis cluster.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-messaging-redis"
    # Tag the cluster with the service that uses it.
    Service = "messaging"
  })
}
