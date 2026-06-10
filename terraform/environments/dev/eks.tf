module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "autoscaling-chaos-dev"
  kubernetes_version = "1.32"

  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    vpc-cni = {}

    kube-proxy = {}

    coredns = {}
  }

  eks_managed_node_groups = {

    bootstrap = {
      instance_types = ["t4g.large"]

      ami_type = "AL2023_ARM_64_STANDARD"

      min_size     = 2
      max_size     = 4
      desired_size = 2

      labels = {
        role = "bootstrap"
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      "karpenter.sh/discovery" = "autoscaling-chaos-dev"
    }
  )
}