# Create the security group that allows application traffic from inside the VPC to reach PostgreSQL.
resource "aws_security_group" "rds" {
  # Give the security group a stable name derived from the cluster name.
  name = "${local.name}-rds-sg"
  # Describe the purpose of the security group in the AWS console.
  description = "Allow PostgreSQL traffic from workloads inside the VPC."
  # Attach the security group to the shared VPC created earlier.
  vpc_id = module.vpc.vpc_id

  # Allow PostgreSQL traffic from any source inside the VPC CIDR.
  ingress {
    # Describe the ingress rule in the AWS console.
    description = "PostgreSQL from the VPC."
    # Open the standard PostgreSQL port.
    from_port = local.postgres_port
    # Close the rule at the same PostgreSQL port.
    to_port = local.postgres_port
    # Restrict the rule to TCP traffic.
    protocol = "tcp"
    # Allow the full VPC CIDR so Auto Mode-managed nodes can always connect.
    cidr_blocks = [local.vpc_cidr]
  }

  # Allow all outbound traffic so the RDS instances can reach AWS-managed dependencies if needed.
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
    Name = "${local.name}-rds-sg"
  })
}

# Group the private subnets into a subnet group that RDS can place databases into.
resource "aws_db_subnet_group" "this" {
  # Give the subnet group a stable name derived from the cluster name.
  name = "${local.name}-rds-subnet-group"
  # Use the private subnets so databases never receive public IP addresses.
  subnet_ids = module.vpc.private_subnets

  # Apply the shared tag set to the subnet group.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-rds-subnet-group"
  })
}

# Create the PostgreSQL instance used by the authentication service.
resource "aws_db_instance" "auth" {
  # Give the instance a stable identifier derived from the cluster name.
  identifier = "${local.name}-auth-db"
  # Use PostgreSQL as the database engine.
  engine = "postgres"
  # Pin the engine major version to a current release.
  engine_version = "16"
  # Choose a small instance class suitable for a development environment.
  instance_class = "db.t3.micro"
  # Allocate a modest amount of storage for the database volume.
  allocated_storage = 20
  # Use gp3 storage for better defaults than the older gp2 class.
  storage_type = "gp3"
  # Encrypt the storage volume at rest.
  storage_encrypted = true

  # Create the database name expected by the current Django settings.
  db_name = local.auth_database_name
  # Set the master username from Terraform input.
  username = var.db_username
  # Ask Amazon RDS to generate and store the password in Secrets Manager instead of Terraform state.
  manage_master_user_password = true

  # Place the database into the private subnet group created above.
  db_subnet_group_name = aws_db_subnet_group.this.name
  # Attach the database security group created above.
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Keep the deployment single-AZ for lower cost in development.
  multi_az = false
  # Ensure the database is not exposed directly to the public internet.
  publicly_accessible = false
  # Allow the stack to be destroyed without forcing a manual snapshot workflow.
  skip_final_snapshot = true
  # Disable deletion protection so the stack can be replaced during iteration.
  deletion_protection = false

  # Retain automated backups for a short development-friendly window.
  backup_retention_period = 7
  # Choose a predictable backup window.
  backup_window = "03:00-04:00"
  # Choose a predictable maintenance window.
  maintenance_window = "mon:04:00-mon:05:00"

  # Apply the shared tag set to the database instance.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-auth-db"
    # Tag the instance with the service that uses it.
    Service = "authentication"
  })
}

# Create the PostgreSQL instance used by the messaging service.
resource "aws_db_instance" "messaging" {
  # Give the instance a stable identifier derived from the cluster name.
  identifier = "${local.name}-messaging-db"
  # Use PostgreSQL as the database engine.
  engine = "postgres"
  # Pin the engine major version to a current release.
  engine_version = "16"
  # Choose a small instance class suitable for a development environment.
  instance_class = "db.t3.micro"
  # Allocate a modest amount of storage for the database volume.
  allocated_storage = 20
  # Use gp3 storage for better defaults than the older gp2 class.
  storage_type = "gp3"
  # Encrypt the storage volume at rest.
  storage_encrypted = true

  # Create the database name expected by the current Django settings.
  db_name = local.messaging_database_name
  # Set the master username from Terraform input.
  username = var.db_username
  # Ask Amazon RDS to generate and store the password in Secrets Manager instead of Terraform state.
  manage_master_user_password = true

  # Place the database into the private subnet group created above.
  db_subnet_group_name = aws_db_subnet_group.this.name
  # Attach the database security group created above.
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Keep the deployment single-AZ for lower cost in development.
  multi_az = false
  # Ensure the database is not exposed directly to the public internet.
  publicly_accessible = false
  # Allow the stack to be destroyed without forcing a manual snapshot workflow.
  skip_final_snapshot = true
  # Disable deletion protection so the stack can be replaced during iteration.
  deletion_protection = false

  # Retain automated backups for a short development-friendly window.
  backup_retention_period = 7
  # Choose a predictable backup window.
  backup_window = "03:00-04:00"
  # Choose a predictable maintenance window.
  maintenance_window = "mon:04:00-mon:05:00"

  # Apply the shared tag set to the database instance.
  tags = merge(local.tags, {
    # Override the Name tag with the resource-specific name.
    Name = "${local.name}-messaging-db"
    # Tag the instance with the service that uses it.
    Service = "messaging"
  })
}
