# Messaging API EKS Architecture

This directory now contains a complete Terraform root module for the Messaging API platform.

The stack creates:

1. A dedicated VPC spread across three Availability Zones in `us-east-1`.
2. An Amazon EKS Auto Mode cluster with managed compute, ALB integration, and EBS support.
3. Two PostgreSQL RDS instances.
4. Two Redis ElastiCache replication groups.
5. AWS Secrets Manager integration through EKS Pod Identity and the AWS Secrets Store CSI provider.
6. An EKS Auto Mode `IngressClassParams` and `IngressClass` for a shared ALB.
7. A Helm release that deploys the Authentication and Messaging services into the cluster.

## High-Level Layout

```text
Internet
  |
  v
Application Load Balancer
  |
  +--> /auth --> authentication-service (ClusterIP, ALB IP targets) --> Authentication Django pod
  |                                                 --> auth-celery worker
  |
  +--> /api  --> messaging-service (ClusterIP, ALB IP targets)      --> Messaging Django pod
                                                    --> messaging-celery worker

Authentication Django pod --> AWS Secrets Manager (JWT + auth DB password)
Authentication Django pod --> Auth PostgreSQL RDS
Authentication Django pod --> Auth Redis ElastiCache over TLS

Messaging Django pod --> AWS Secrets Manager (JWT + messaging DB password)
Messaging Django pod --> Messaging PostgreSQL RDS
Messaging Django pod --> Messaging Redis ElastiCache over TLS
Messaging Django pod --> gRPC call to authentication-service:50051
```

## File Guide

`providers.tf`

- Declares Terraform and provider requirements.
- Configures the AWS provider.
- Reads the EKS cluster back after creation.
- Configures the Kubernetes and Helm providers against the new cluster.

`variables.tf`

- Holds the deployment inputs such as AWS profile, database credentials, access token, domain name, and Helm release name.

`locals.tf`

- Central place for reusable names, ports, namespaces, tags, subnet matching, and the Kubernetes version.

`vpc.tf`

- Creates the VPC, public subnets, private subnets, intra subnets, route tables, and NAT gateway through the community VPC module.

`iam.tf`

- Creates the EKS cluster IAM role.
- Creates the EKS Auto Mode node IAM role.
- Attaches the AWS-managed policies required by Auto Mode.

`eks.tf`

- Creates the EKS Auto Mode cluster.
- Enables API authentication mode.
- Enables bootstrap admin access for the cluster creator.
- Enables managed compute, load balancing, and block storage.
- Optionally creates an explicit EKS access entry for another IAM principal.

`rds.tf`

- Creates the PostgreSQL security group and subnet group.
- Creates one RDS instance for the Authentication service.
- Creates one RDS instance for the Messaging service.
- Enables RDS-managed Secrets Manager passwords instead of plain Terraform-managed DB passwords.

`elastic-cache.tf`

- Creates the Redis security group and subnet group.
- Creates one Redis replication group for the Authentication service.
- Creates one Redis replication group for the Messaging service.
- Enables in-transit encryption so the apps use `rediss://`.

`secrets-manager.tf`

- Creates or references the shared JWT signing secret in AWS Secrets Manager.
- Installs the AWS Secrets Store CSI provider EKS add-on.
- Creates least-privilege IAM roles for authentication and messaging workloads.
- Associates those IAM roles to Kubernetes service accounts with EKS Pod Identity.

`alb.tf`

- Creates the EKS Auto Mode `IngressClassParams`.
- Creates the `IngressClass` named `alb`.
- Configures both app ingresses to share one ALB through an ingress group.

`helm.tf`

- Installs the local `messaging-system` Helm chart.
- Injects the RDS and ElastiCache endpoints into chart values.
- Injects the Secrets Manager ARNs and service-account names into chart values.
- Disables the chart’s old in-cluster Postgres and Redis resources during Terraform deployment.

`outputs.tf`

- Exposes the useful environment outputs such as cluster name, cluster endpoint, VPC ID, and the data-service hosts.

## Application Notes

The Helm chart was updated so it can run in two modes:

1. Managed AWS dependencies.
   This is the Terraform path. Terraform sets the chart values so the services use RDS, ElastiCache, Secrets Manager, the Secrets Store CSI integration, and the internal Postgres/Redis resources stay disabled.

2. Local in-cluster dependencies.
   If you install the chart by itself and keep the default values, the old in-cluster Postgres and Redis objects are still available and the chart falls back to Kubernetes `Secret`s.

Other chart fixes included:

- Namespace manifests no longer include a `status` field.
- App secrets fall back to `stringData` only when Secrets Manager mode is disabled.
- App services now use `ClusterIP`, and the ALB ingress targets pod IPs directly through `alb.ingress.kubernetes.io/target-type: ip`.
- The ingress resources now rely on the `alb` ingress class instead of old ALB annotations for core setup.
- In Secrets Manager mode, the pods mount AWS secrets through the CSI driver instead of reading DB credentials from Kubernetes `Secret`s.

## Required Inputs

At minimum, provide:

- `db_username`

Optional but useful:

- `domain_name`
- `alb_scheme`
- `deploy_in_cluster_resources`
- `existing_access_token_secret_arn`
- `auth_image`
- `messaging_image`
- `enable_cluster_admin_access_entry`
- `cluster_admin_principal_arn`

## Suggested Usage

Run from the `Terraform` directory:

```bash
terraform init
terraform plan \
  -var="deploy_in_cluster_resources=false" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=arn:aws:secretsmanager:us-east-1:123456789012:secret:my-shared-jwt"
terraform apply \
  -var="deploy_in_cluster_resources=false" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=arn:aws:secretsmanager:us-east-1:123456789012:secret:my-shared-jwt"
```

## Deployment Steps

Use this order when deploying the stack from a clean machine.

1. Make sure the required tools are installed:
   `terraform`, `aws`, `kubectl`, and `helm`

2. Make sure your AWS credentials can create:
   EKS, VPC, RDS, ElastiCache, IAM, and Secrets Manager resources

3. Create the shared JWT secret in AWS Secrets Manager before running Terraform.

```bash
aws secretsmanager create-secret \
  --name messaging-api-shared-access-token \
  --secret-string '{"access_token":"replace-with-a-long-random-secret"}' \
  --region us-east-1 \
  --profile Saar
```

4. Retrieve the secret ARN and use it in Terraform.

```bash
aws secretsmanager describe-secret \
  --secret-id messaging-api-shared-access-token \
  --region us-east-1 \
  --profile Saar
```

5. Deploy the AWS infrastructure from the `Terraform` directory.

```bash
terraform init
terraform plan \
  -var="deploy_in_cluster_resources=false" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=YOUR_SECRET_ARN"
terraform apply \
  -var="deploy_in_cluster_resources=false" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=YOUR_SECRET_ARN"
```

6. Deploy the in-cluster Kubernetes manifests and Helm release after EKS is active.

```bash
terraform apply \
  -var="deploy_in_cluster_resources=true" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=YOUR_SECRET_ARN"
```

7. Optional overrides you can pass during plan or apply:

- `-var="aws_profile=Saar"`
- `-var="domain_name=your-domain.com"`
- `-var='certificate_arns=["arn:aws:acm:..."]'`

If you leave `domain_name` empty, the ingress matches all hosts and you can use the AWS-provided ALB DNS name directly for testing.

8. Update your kubeconfig after the cluster exists.

```bash
aws eks update-kubeconfig \
  --name messaging-api-cluster \
  --region us-east-1 \
  --profile Saar
```

9. Verify the deployment.

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
kubectl get secretproviderclass -A
terraform output
```

10. For a throwaway or test environment, you can use the ALB DNS name shown in `kubectl get ingress -A` directly.

11. Point your DNS record to the ALB created for the ingress only if you want external access on your own host name.

12. If Terraform reports `cannot create REST client: no client config`, it means the EKS control plane is not available yet for Kubernetes and Helm resources. Apply once with `deploy_in_cluster_resources=false`, wait for EKS to finish creating, and then run a second apply with `deploy_in_cluster_resources=true`.

### Minimal Deploy

```bash
cd Terraform
terraform init
terraform apply \
  -var="deploy_in_cluster_resources=false" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=YOUR_SECRET_ARN"
terraform apply \
  -var="deploy_in_cluster_resources=true" \
  -var="db_username=postgres" \
  -var="existing_access_token_secret_arn=YOUR_SECRET_ARN"
aws eks update-kubeconfig \
  --name messaging-api-cluster \
  --region us-east-1 \
  --profile Saar
kubectl get pods -A
kubectl get ingress -A
```

After the cluster exists, update kubeconfig:

```bash
aws eks update-kubeconfig --name messaging-api-cluster --region us-east-1 --profile Saar
```

Then verify:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
```

## Practical Notes

- Because the same root module creates the EKS cluster and then immediately uses Kubernetes and Helm providers, a second `terraform apply` can occasionally be useful if the control plane is technically created but not yet fully ready for follow-up API operations.
- The stack now uses RDS-managed Secrets Manager passwords, so Terraform no longer needs a plain `db_password` input.
- The stack uses the AWS Secrets Store CSI integration plus EKS Pod Identity so pods read AWS secrets without long-lived static AWS credentials.
- The stack now uses Redis TLS, so the chart builds `rediss://` broker URLs at runtime.
- If Terraform creates the shared access-token secret for you, that generated value still exists in Terraform state. The cleanest long-term setup is to create that secret out of band and pass `existing_access_token_secret_arn`.
- The stack keeps the PostgreSQL database name as `postgres` because the current Django settings hardcode that name.
- The old chart’s hostPath storage was left available only for the optional local in-cluster mode. Terraform-driven deployments now use managed AWS data services instead.

## Source References

The EKS Auto Mode pieces in this directory were aligned with the AWS documentation:

- EKS Auto Mode cluster IAM role:
  https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html
- EKS Auto Mode node IAM role:
  https://docs.aws.amazon.com/eks/latest/userguide/auto-create-node-role.html
- EKS API access entries:
  https://docs.aws.amazon.com/eks/latest/userguide/setting-up-access-entries.html
- EKS Auto Mode ALB ingress classes:
  https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html
- EKS Auto Mode cluster creation flow:
  https://docs.aws.amazon.com/eks/latest/userguide/automode-get-started-cli.html
- AWS Secrets Manager on EKS with Pod Identity:
  https://docs.aws.amazon.com/secretsmanager/latest/userguide/ascp-pod-identity-integration.html
- AWS Secrets and Configuration Provider installation on EKS:
  https://docs.aws.amazon.com/secretsmanager/latest/userguide/ascp-eks-installation.html
