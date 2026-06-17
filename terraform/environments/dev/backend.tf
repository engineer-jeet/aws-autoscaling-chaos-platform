terraform {
  backend "s3" {
    bucket         = var.tf_state_bucket
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "aws-autoscaling-chaos-platform-locks"
    encrypt        = true
  }
}