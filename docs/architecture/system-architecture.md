# Messaging API EKS Architecture Diagram

This file is the text source for the deployed AWS architecture.

It reflects the Terraform-managed EKS deployment path, not the Helm chart's local fallback mode with in-cluster Postgres and Redis.

## Runtime Topology

```mermaid
flowchart TB
    Client[Client / Browser / Smoke Test]

    subgraph AWS["AWS Account - us-east-1"]
        subgraph VPC["VPC - 10.0.0.0/16"]
            subgraph Public["Public Subnets"]
                ALB[Shared Application Load Balancer<br/>EKS Auto Mode ingress class: alb]
            end

            subgraph Private["Private Subnets"]
                subgraph EKS["Amazon EKS Auto Mode Cluster<br/>messaging-api-cluster"]
                    CSI[AWS Secrets Store CSI provider add-on]
                    PodIdentity[EKS Pod Identity]

                    subgraph AuthNS["Namespace: authentication"]
                        AuthIngress[Ingress rule<br/>/auth]
                        AuthSvc[authentication-service<br/>ClusterIP<br/>HTTP 8001 / gRPC 50051]
                        AuthWeb[authentication deployment<br/>Django + Gunicorn 8001<br/>gRPC server 50051]
                        AuthCelery[auth-celery deployment<br/>Celery worker]
                        AuthSA[ServiceAccount<br/>auth-workload]
                        AuthSPC[SecretProviderClass<br/>auth-aws-secrets]
                    end

                    subgraph MsgNS["Namespace: messaging"]
                        MsgIngress[Ingress rule<br/>/api]
                        MsgSvc[messaging-service<br/>ClusterIP<br/>HTTP 8000]
                        MsgWeb[messaging deployment<br/>Django + Gunicorn 8000]
                        MsgCelery[messaging-celery deployment<br/>Celery worker]
                        MsgSA[ServiceAccount<br/>messaging-workload]
                        MsgSPC[SecretProviderClass<br/>messaging-aws-secrets]
                    end
                end

                subgraph Data["Managed Data Services"]
                    AuthRDS[(Auth PostgreSQL RDS)]
                    MsgRDS[(Messaging PostgreSQL RDS)]
                    AuthRedis[(Auth Redis ElastiCache<br/>TLS enabled)]
                    MsgRedis[(Messaging Redis ElastiCache<br/>TLS enabled)]
                end
            end

            subgraph Secrets["AWS Secrets Manager"]
                JwtSecret[(Shared JWT secret<br/>access_token)]
                AuthDbSecret[(Auth DB master secret)]
                MsgDbSecret[(Messaging DB master secret)]
            end
        end
    end

    Client -->|HTTP / HTTPS| ALB
    ALB -->|/auth| AuthIngress
    ALB -->|/api| MsgIngress

    AuthIngress --> AuthSvc
    MsgIngress --> MsgSvc

    AuthSvc -->|HTTP 8001| AuthWeb
    AuthSvc -->|gRPC 50051| AuthWeb
    MsgSvc -->|HTTP 8000| MsgWeb

    MsgWeb -->|gRPC token validation| AuthSvc

    AuthWeb -->|SQL 5432| AuthRDS
    AuthCelery -->|SQL 5432| AuthRDS
    MsgWeb -->|SQL 5432| MsgRDS
    MsgCelery -->|SQL 5432| MsgRDS

    AuthWeb -->|Redis TLS 6379| AuthRedis
    AuthCelery -->|Redis TLS 6379| AuthRedis
    MsgWeb -->|Redis TLS 6379| MsgRedis
    MsgCelery -->|Redis TLS 6379| MsgRedis

    AuthSA -.->|pod identity association| PodIdentity
    MsgSA -.->|pod identity association| PodIdentity

    AuthWeb -->|mount /mnt/secrets-store| AuthSPC
    AuthCelery -->|mount /mnt/secrets-store| AuthSPC
    MsgWeb -->|mount /mnt/secrets-store| MsgSPC
    MsgCelery -->|mount /mnt/secrets-store| MsgSPC

    AuthSPC -->|uses provider: aws| CSI
    MsgSPC -->|uses provider: aws| CSI

    CSI -->|GetSecretValue| JwtSecret
    CSI -->|GetSecretValue| AuthDbSecret
    CSI -->|GetSecretValue| MsgDbSecret

    AuthSPC -->|access-token| JwtSecret
    AuthSPC -->|postgres username/password| AuthDbSecret
    MsgSPC -->|access-token| JwtSecret
    MsgSPC -->|postgres username/password| MsgDbSecret
```

## Provisioning Flow

```mermaid
flowchart LR
    Dev[Developer / CI]
    TF[Terraform root module]
    Helm[helm_release.messaging_system]

    subgraph AWSInfra["AWS infrastructure created by Terraform"]
        VPC[VPC + subnets + NAT + route tables]
        EKS[Amazon EKS Auto Mode cluster]
        RDS[RDS PostgreSQL instances]
        Redis[ElastiCache Redis replication groups]
        SM[Secrets Manager secrets]
        PI[Pod Identity associations]
        ALBClass[IngressClassParams + IngressClass]
    end

    subgraph K8sObjects["Kubernetes objects created by Helm"]
        NS[Namespaces]
        SA[ServiceAccounts]
        Deployments[Web + Celery deployments]
        Services[ClusterIP services]
        Ingresses[Ingress rules]
        SPCs[SecretProviderClasses]
    end

    Dev -->|terraform apply| TF
    TF --> AWSInfra
    TF --> Helm
    Helm --> K8sObjects
```

## Notes

- Both application services are exposed through one shared ALB and path-based routing.
- `authentication-service` serves both REST traffic on port `8001` and gRPC on port `50051`.
- `messaging-service` serves REST traffic on port `8000` and calls the authentication service over gRPC for token validation.
- The Django web pods and Celery workers in each namespace share the same service account, Pod Identity role, and SecretProviderClass.
- In the Terraform-managed deployment, the in-cluster Postgres and Redis manifests from the chart are disabled.
