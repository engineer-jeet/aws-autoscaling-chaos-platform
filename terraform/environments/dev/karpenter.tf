data "aws_caller_identity" "current" {}

locals {
  karpenter_namespace      = "kube-system"
  karpenter_serviceaccount = "karpenter"
}

data "aws_iam_policy_document" "karpenter_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        module.eks.oidc_provider_arn
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:sub"

      values = [
        "system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_serviceaccount}"
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name = "${module.eks.cluster_name}-karpenter-controller"

  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role.json

  tags = local.common_tags
}