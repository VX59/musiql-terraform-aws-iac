terraform {
  backend "s3" {
    bucket = "musiql-terraform-state"
    key = "musiql-aws-iac/terraform.tfstate"
    region = "us-east-2"
  }
}