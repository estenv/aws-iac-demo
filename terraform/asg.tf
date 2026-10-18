# 7. Auto scaling group (1-3 instances, ELB health checks).
resource "aws_autoscaling_group" "this" {
  name = "tf-asg"

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # target_group_arns attaches the group to the target group directly.
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  force_delete              = true

  tag {
    key                 = "Name"
    value               = "tf-asg"
    propagate_at_launch = true
  }
}

# 8. High CPU alarm.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "tf-cpu-high"
  alarm_description   = "Scale out when average CPU exceeds 40% for 5 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 40
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
}

# 9. Low CPU alarm.
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "tf-cpu-low"
  alarm_description   = "Scale in when average CPU is below 10% for 5 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 10
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
}

# 10. Scale-out step policy (+1 when CPU >= 40).
resource "aws_autoscaling_policy" "scale_out" {
  name                      = "tf-scale-out"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 300

  step_adjustment {
    metric_interval_lower_bound = 40
    scaling_adjustment          = 1
  }
}

# 11. Scale-in step policy (-1 when CPU <= 10).
resource "aws_autoscaling_policy" "scale_in" {
  name                      = "tf-scale-in"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 300

  # An upper-bounded step requires a following unbounded step.
  step_adjustment {
    metric_interval_upper_bound = 10
    scaling_adjustment          = -1
  }

  step_adjustment {
    metric_interval_lower_bound = 10
    scaling_adjustment          = 0
  }
}
