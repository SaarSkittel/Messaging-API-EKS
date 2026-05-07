# Install the application Helm chart after the infrastructure and Kubernetes entry points are ready.
resource "helm_release" "messaging_system" {
  # Use the caller-supplied Helm release name.
  name = var.release_name
  # Point Helm at the local chart directory inside this repository.
  chart = "${path.module}/../App-Helm-Charts/helm/messaging-system"
  # Install the release into the default namespace because the chart itself creates the app namespaces.
  namespace = "default"
  # Wait for Kubernetes objects to become ready before Terraform considers the release successful.
  wait = true
  # Give the release ample time because EKS Auto Mode may need to create nodes, load balancers, and DNS entries.
  timeout = 900
  # Remove partially-created resources if Helm fails during the install or upgrade.
  cleanup_on_fail = true
  # Reuse values from Terraform only and avoid hidden drift from previous Helm state.
  reuse_values = false

  # Pass a generated values document that wires the chart to the AWS-managed data services created above.
  values = [
    yamlencode({
      domainName                       = var.domain_name
      ingressClassName                 = local.alb_ingress_class_name
      authNamespace                    = local.auth_namespace
      messagingNamespace               = local.messaging_namespace
      authServiceAccountName           = local.auth_service_account_name
      messagingServiceAccountName      = local.messaging_service_account_name
      authSecretProviderClassName      = local.auth_secret_provider_class_name
      messagingSecretProviderClassName = local.messaging_secret_provider_class_name
      authImage                        = var.auth_image
      messagingImage                   = var.messaging_image
      useSecretsManager                = true
      useRedisTls                      = true
      accessTokenSecretArn             = local.access_token_secret_arn
      authDatabaseSecretArn            = aws_db_instance.auth.master_user_secret[0].secret_arn
      messagingDatabaseSecretArn       = aws_db_instance.messaging.master_user_secret[0].secret_arn
      authPostgresHost                 = aws_db_instance.auth.address
      authPostgresPort                 = local.postgres_port
      messagingPostgresHost            = aws_db_instance.messaging.address
      messagingPostgresPort            = local.postgres_port
      authRedisHost                    = aws_elasticache_replication_group.auth.primary_endpoint_address
      authRedisPort                    = local.redis_port
      messagingRedisHost               = aws_elasticache_replication_group.messaging.primary_endpoint_address
      messagingRedisPort               = local.redis_port
      deployInternalAuthPostgres       = false
      deployInternalAuthRedis          = false
      deployInternalMessagingPostgres  = false
      deployInternalMessagingRedis     = false
    })
  ]

  # Wait for the cluster, ingress class, databases, and caches before installing the workloads.
  depends_on = [
    kubernetes_manifest.alb_ingress_class,
    aws_eks_addon.secrets_store_csi_provider,
    aws_eks_pod_identity_association.auth,
    aws_eks_pod_identity_association.messaging,
    aws_db_instance.auth,
    aws_db_instance.messaging,
    aws_elasticache_replication_group.auth,
    aws_elasticache_replication_group.messaging,
  ]
}
