# Share the default VPC; never create a VPC or NAT gateway.
data "aws_vpc" "default" {
  default = true
}

# Default-VPC subnets. Restricted to two well-provisioned AZs; us-east-1e (and
# the other default AZs) are capacity-constrained in this account.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b"]
  }
}
