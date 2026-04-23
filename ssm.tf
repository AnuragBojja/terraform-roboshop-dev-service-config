resource "aws_ssm_parameter" "ami_id" {
  name  = "/${var.project_name}/${var.env}/${var.service_name}_ami_id"
  type  = "String"
  value = aws_ami_from_instance.main.id
}