variable "region" {
  description = "AWS region to deploy the runner fleet into."
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  description = "Prefix applied to all created AWS resource names."
  type        = string
  default     = "gitlab-runner-ec2autoscale"
}

variable "instance_type" {
  description = "EC2 instance type used for CI job instances."
  type        = string
  default     = "t3.medium"
}

variable "ami_name_prefix" {
  description = "Name prefix of the Packer-built worker AMI to look up (must match Packer's ami_name_prefix)."
  type        = string
  default     = "gitlab-runner-ec2autoscale"
}

variable "ami_id" {
  description = "Optional explicit AMI id to pin. If empty, the newest self-owned AMI matching ami_name_prefix is used."
  type        = string
  default     = ""
}

variable "max_instances" {
  description = "Maximum number of EC2 instances the ASG (and fleeting plugin) may run."
  type        = number
  default     = 10
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB) for each job instance."
  type        = number
  default     = 30
}

variable "ssh_user" {
  description = "SSH username exposed by the AMI (Amazon Linux 2023 -> ec2-user)."
  type        = string
  default     = "ec2-user"
}

variable "manager_cidr" {
  description = "CIDR allowed to SSH into job instances (the runner manager host's public IP, e.g. 203.0.113.10/32)."
  type        = string
}

variable "subnet_ids" {
  description = "Optional explicit subnet IDs for the ASG. If empty, all subnets of the default VPC are used."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
