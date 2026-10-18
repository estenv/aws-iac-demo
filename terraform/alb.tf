# 5. Internet-facing Application Load Balancer.
resource "aws_lb" "this" {
  name               = "tf-alb"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "tf-alb"
  }
}

# 4. Target group.
resource "aws_lb_target_group" "this" {
  name             = "tf-tg"
  port             = 80
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "instance"
  vpc_id           = data.aws_vpc.default.id

  health_check {
    enabled  = true
    path     = "/health.php"
    port     = 80
    protocol = "HTTP"
    matcher  = "200"
  }

  tags = {
    Name = "tf-tg"
  }
}

# 6. HTTP listener forwarding to the target group.
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
