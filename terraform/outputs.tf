output "alb_dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.this.arn
}

output "asg_name" {
  description = "Name of the auto scaling group"
  value       = aws_autoscaling_group.this.name
}
