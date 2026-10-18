# 3. Launch template. No key pair, no instance profile, no user-data.
resource "aws_launch_template" "this" {
  name = "tf-lt"

  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [aws_security_group.ec2.id]

  tags = {
    Name = "tf-lt"
  }
}
