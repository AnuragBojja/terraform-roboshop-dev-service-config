#creating ec2 instance for service
resource "aws_instance" "main" {
  ami           = local.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [local.sg_id]
  subnet_id = local.subnet_id
  iam_instance_profile = aws_iam_instance_profile.Main-SSM-Role.name

  tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.service_name}"
    }
  )
}

#attaching iam role to main instance
resource "aws_iam_instance_profile" "Main-SSM-Role" {
  name = "${var.service_name}-SSM-Role"
  role = "EC2SSMParameterStore"
  }

#this will run every time the instance created or changed 
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]
#connection block to connect main from bastein 
  connection {
    type = "ssh"
    user = "ec2-user"
    password = local.shh_loginpass
    host = aws_instance.main.private_ip
  }
# running bootstrap.sh scripts
  provisioner "file" {
    source = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [ 
        "chmod +x /tmp/bootstrap.sh",
        "sudo /tmp/bootstrap.sh ${var.service_name} ${var.env}"
     ]
  }
}
#Stoping configured instance
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [ terraform_data.main ]
}

# creating ami using instance 
resource "aws_ami_from_instance" "main" {
  name               = "${local.common_name}-${var.service_name}-ami"
  source_instance_id = aws_instance.main.id
  depends_on = [ aws_ec2_instance_state.main ]
  tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.service_name}-ami"
    }
  )
}
#source:: https://registry.terraform.io/providers/-/aws/6.3.0/docs/resources/launch_template
resource "aws_launch_template" "main" {
  name = "${local.common_name}-${var.service_name}"

  image_id = aws_ami_from_instance.main.id

  instance_initiated_shutdown_behavior = "terminate"
  instance_type = var.instance_type
  vpc_security_group_ids = [local.sg_id]
  #when ever we do terraform init new version of ami will be created with new ami id
  update_default_version = true
  
  #tags attached to instance 
  tag_specifications {
    resource_type = "instance"

    tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.service_name}"
    }
  )
  }

#tags attached to volume 
  tag_specifications {
    resource_type = "volume"

    tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.service_name}"
    }
  )
  }
#tags attached to lanch template 
  tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.service_name}"
    }
  )

}

#source:: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
resource "aws_lb_target_group" "main" {
  name     = "${local.common_name}-${var.service_name}"
  port     = local.health_check_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60
  health_check {
    enabled             = true
    path                = local.health_check_path
    protocol            = "HTTP"
    port                = local.health_check_port
    matcher             = "200-299"
    interval            = 10
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

#source :: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
resource "aws_autoscaling_group" "main" {
  name                      = "${local.common_name}-${var.service_name}"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = false
  vpc_zone_identifier       = local.subnet_ids
  launch_template {
    id = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }
  target_group_arns = [ aws_lb_target_group.main.arn ]
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  
  timeouts {
    delete = "15m"
  }

  dynamic "tag" {
    for_each = merge(
                        local.common_tags,
                        {
                            Name = "${local.common_name}-${var.service_name}"
                        }
                    )
    content {
        key                 = tag.key
        value               = tag.value
        propagate_at_launch = false
        }
  }
}


#source :: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy
resource "aws_autoscaling_policy" "main" {
  name = "${local.common_name}-${var.service_name}"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}

#source :: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule
resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  condition {
    host_header {
      values = [local.host_header]
    }
  }
}



# resource "terraform_data" "catalogue_local" {
#   triggers_replace = [
#     aws_instance.catalogue.id
#   ]
#   provisioner "local-exec" {
#     command = "aws ec2 terminate-instances --instance-ids ${aws_instance.catalogue.id}"
#   }
#   depends_on = [ aws_autoscaling_policy.catalogue ]
# }