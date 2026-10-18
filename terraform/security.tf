# 1. ALB security group: inbound HTTP from the deploying host only.
resource "aws_security_group" "alb" {
  name        = "tf-alb-sg"
  description = "tf ALB - inbound HTTP from the deploying host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from deploying host"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.alb_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-alb-sg"
  }
}

# 2. Instance security group: inbound HTTP from the ALB security group only.
#    The connection source is the ALB, not the client, so this is required.
resource "aws_security_group" "ec2" {
  name        = "tf-ec2-sg"
  description = "tf EC2 - inbound HTTP from the ALB security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-ec2-sg"
  }
}
