provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project       = "iac-demo"
      ProvisionedBy = "terraform"
    }
  }
}
