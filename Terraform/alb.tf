# Create the EKS Auto Mode IngressClassParams object that describes how the shared ALB should behave.
resource "kubernetes_manifest" "alb_ingress_class_params" {
  # Submit the manifest directly because IngressClassParams is a CRD owned by EKS Auto Mode.
  manifest = {
    # Use the API group required by EKS Auto Mode.
    apiVersion = "eks.amazonaws.com/v1"
    # Create an IngressClassParams custom resource.
    kind = "IngressClassParams"
    # Set the Kubernetes metadata for the custom resource.
    metadata = {
      # Name the resource so the IngressClass can reference it.
      name = local.alb_ingress_class_name
    }
    # Build the ALB behavior spec.
    spec = merge({
      # Choose whether the ALB is public or internal.
      scheme = var.alb_scheme
      # Group both ingress resources behind one ALB instead of creating one per namespace.
      group = {
        # Use the cluster name as the shared group identifier.
        name = local.alb_group_name
      }
      # Restrict this ingress class to the namespaces used by the application.
      namespaceSelector = {
        # Match namespaces by their built-in metadata label.
        matchExpressions = [
          {
            # Select against the Kubernetes namespace name label.
            key = "kubernetes.io/metadata.name"
            # Require the namespace label to be in the allowed list.
            operator = "In"
            # Allow only the two application namespaces.
            values = [local.auth_namespace, local.messaging_namespace]
          }
        ]
      }
      # Tell EKS Auto Mode how to discover the correct subnets for the ALB.
      subnets = {
        # Match subnets by the standard EKS load-balancer role tags.
        matchTags = local.alb_subnet_match_tags
      }
      }, length(var.certificate_arns) > 0 ? {
      # Attach ACM certificates only when the caller supplied them.
      certificateARNs = var.certificate_arns
    } : {})
  }

  # Wait for the EKS control plane before submitting this cluster-scoped custom resource.
  depends_on = [aws_eks_cluster.cluster]
}

# Create the Kubernetes IngressClass that points normal ingress resources at the ALB configuration above.
resource "kubernetes_manifest" "alb_ingress_class" {
  # Submit the manifest directly because this keeps the spec close to the AWS documentation examples.
  manifest = {
    # Use the stable Kubernetes networking API group.
    apiVersion = "networking.k8s.io/v1"
    # Create an IngressClass resource.
    kind = "IngressClass"
    # Set the Kubernetes metadata for the ingress class.
    metadata = {
      # Name the ingress class so application ingresses can reference it.
      name = local.alb_ingress_class_name
      # Add standard annotations to the ingress class.
      annotations = {
        # Make this the default ingress class for convenience.
        "ingressclass.kubernetes.io/is-default-class" = "true"
      }
    }
    # Build the ingress class spec.
    spec = {
      # Route this ingress class to the EKS Auto Mode ALB controller.
      controller = "eks.amazonaws.com/alb"
      # Reference the IngressClassParams custom resource created above.
      parameters = {
        # Use the EKS API group for the parameters reference.
        apiGroup = "eks.amazonaws.com"
        # Reference the IngressClassParams kind.
        kind = "IngressClassParams"
        # Reference the resource by name.
        name = local.alb_ingress_class_name
      }
    }
  }

  # Wait for the IngressClassParams custom resource before creating the IngressClass.
  depends_on = [kubernetes_manifest.alb_ingress_class_params]
}
