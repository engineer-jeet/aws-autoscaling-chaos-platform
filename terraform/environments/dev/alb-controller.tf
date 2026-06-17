resource "aws_iam_role" "alb_controller" {
  name = "autoscaling-chaos-dev-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Federated = module.eks.oidc_provider_arn
      }

      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = "<ALB_CONTROLLER_POLICY_ARN>"
}

