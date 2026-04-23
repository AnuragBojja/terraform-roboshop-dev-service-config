locals {
  common_tags = {
    Project_name = var.project_name
    Env = var.env
    Terraform = "true"
  }
  common_name = ("${var.project_name}-${var.env}")
  vpc_id = data.aws_ssm_parameter.vpc_id.value
  ami_id = data.aws_ami.roboshop_ami.id
  shh_loginpass = data.aws_ssm_parameter.shh_loginpass.value

  sg_id = data.aws_ssm_parameter.sg_id.value

  private_subnet_id = split(",",data.aws_ssm_parameter.private_subnet_ids.value)[0]
  private_subnet_ids = split(",",data.aws_ssm_parameter.private_subnet_ids.value)
  public_subnet_id = split(",",data.aws_ssm_parameter.public_subnet_ids.value)[0]
  public_subnet_ids = split(",",data.aws_ssm_parameter.public_subnet_ids.value)
  subnet_id = "${var.service_name}" == "frontend" ? local.public_subnet_id : local.private_subnet_id
  subnet_ids = "${var.service_name}" == "frontend" ? local.public_subnet_ids : local.private_subnet_ids

  backend_alb_listener_arn = data.aws_ssm_parameter.backend_alb_listener_arn.value
  frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value
  alb_listener_arn = "${var.service_name}" == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn

  health_check_path = "${var.service_name}" == "frontend" ? "/" : "/health"
  health_check_port = "${var.service_name}" == "frontend" ? 80 : 8080

  host_header = "${var.service_name}" == "frontend" ? "${var.project_name}-${var.env}.${var.domain_name}" : "${var.service_name}.backend-alb-${var.env}.${var.domain_name}"


}