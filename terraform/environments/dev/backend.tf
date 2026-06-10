terraform {
  backend "s3" {
    bucket         = "aws-autoscaling-chaos-platform-tfstate-974318644331"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "aws-autoscaling-chaos-platform-locks"
    encrypt        = true
  }
}