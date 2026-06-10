module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.project}-${local.environment}-vpc"

  cidr = "10.0.0.0/16"

  azs = [
    "ap-south-1a",
    "ap-south-1b",
    "ap-south-1c"
  ]

  public_subnets = [
    "10.0.0.0/24",
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]

  private_subnets = [
    "10.0.16.0/20",
    "10.0.32.0/20",
    "10.0.48.0/20"
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "karpenter.sh/discovery" = "autoscaling-chaos-dev"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "autoscaling-chaos-dev"
  }

  tags = local.common_tags
}