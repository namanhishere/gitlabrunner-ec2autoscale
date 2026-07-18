terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = merge({ Project = var.name_prefix, ManagedBy = "terraform" }, var.tags)
  }
}

# --- Networking: use the default VPC / subnets unless overridden ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default.ids
}

# --- Custom worker AMI built by Packer (Docker + tools + baked CI image) ---
# Looked up by the name prefix Packer stamps on the image. Override with
# var.ami_id to pin a specific AMI.
data "aws_ami" "runner" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["${var.ami_name_prefix}-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.runner.id
}

# --- SSH key pair (generated locally, private key exported to the runner) ---
resource "tls_private_key" "runner" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "runner" {
  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.runner.public_key_openssh
}

# --- Security group: SSH from the manager only, all egress ---
resource "aws_security_group" "runner" {
  name        = "${var.name_prefix}-sg"
  description = "GitLab runner job instances - SSH from manager, egress all"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from the runner manager host"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.manager_cidr]
  }

  egress {
    description = "All outbound (GitLab, image registries, package repos)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Launch template: AL2023 + Docker, docker group for the SSH user ---
resource "aws_launch_template" "runner" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.runner.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.runner.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  # Docker, tools, and the CI image are baked into the AMI by Packer, and a
  # systemd service (pull-ci-image.service) refreshes the image on boot. No
  # user_data provisioning is needed here.

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}-job" }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
}

# --- Auto Scaling Group: managed by the fleeting plugin (starts at 0) ---
resource "aws_autoscaling_group" "runner" {
  name                = "${var.name_prefix}-asg"
  min_size            = 0
  max_size            = var.max_instances
  desired_capacity    = 0
  vpc_zone_identifier = local.subnet_ids

  # Fleeting handles instance replacement itself; disable ASG-side scale-in
  # protection interference and let the plugin manage the fleet.
  protect_from_scale_in = false

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-job"
    propagate_at_launch = true
  }

  # The fleeting plugin drives desired_capacity; ignore drift on it.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
