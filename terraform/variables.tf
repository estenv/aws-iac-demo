variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Pre-baked web server image (us-east-1, x86_64)."
  type        = string
  default     = "ami-06174c8686ce68c26"
}

variable "instance_type" {
  description = "EC2 instance type for the auto scaling group."
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Optional SSH key pair name. Leave empty (no SSH is needed)."
  type        = string
  default     = ""
}

variable "alb_ingress_cidr" {
  description = "CIDR allowed to reach the ALB on port 80 (the deploying host's public IP)."
  type        = string
  default     = "203.0.113.0/24"
}
