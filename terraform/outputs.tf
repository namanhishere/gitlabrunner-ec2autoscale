output "asg_name" {
  description = "Auto Scaling Group name -> set as ASG_NAME in .env."
  value       = aws_autoscaling_group.runner.name
}

output "region" {
  description = "AWS region -> set as AWS_REGION in .env."
  value       = var.region
}

output "access_key_id" {
  description = "IAM access key id for the fleeting plugin -> AWS_ACCESS_KEY_ID in .env."
  value       = aws_iam_access_key.runner.id
}

output "secret_access_key" {
  description = "IAM secret access key for the fleeting plugin -> AWS_SECRET_ACCESS_KEY in .env."
  value       = aws_iam_access_key.runner.secret
  sensitive   = true
}

output "private_key_pem" {
  description = "Private SSH key for the EC2 key pair. Write to ../secrets/ec2-key.pem."
  value       = tls_private_key.runner.private_key_pem
  sensitive   = true
}

output "ami_id" {
  description = "Custom Packer-built worker AMI used for job instances."
  value       = local.ami_id
}
