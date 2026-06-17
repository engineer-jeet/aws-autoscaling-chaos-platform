locals {
  project     = "aws-autoscaling-chaos-platform"
  environment = "dev"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}