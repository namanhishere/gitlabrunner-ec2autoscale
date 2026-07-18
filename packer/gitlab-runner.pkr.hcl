packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "instance_type" {
  description = "Instance type used to build the image (not the runtime type)."
  type        = string
  default     = "t3.medium"
}

variable "ami_name_prefix" {
  description = "Prefix for the produced AMI name. Terraform looks the AMI up by this prefix."
  type        = string
  default     = "gitlab-runner-ec2autoscale"
}

variable "ci_image" {
  description = "CI image on ghcr.io to pre-pull/bake, e.g. ghcr.io/OWNER/IMAGE:latest."
  type        = string
  default     = "ghcr.io/OWNER/IMAGE:latest"
}

variable "ssh_username" {
  type    = string
  default = "ec2-user"
}

# Base Amazon Linux 2023 image (owned by Amazon) to build on top of.
source "amazon-ebs" "runner" {
  region        = var.region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "GitLab Runner CI worker: Docker + tools, CI image pre-baked"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      architecture        = "x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.ami_name_prefix}"
    Project = var.ami_name_prefix
    Role    = "gitlab-runner-worker"
  }
}

build {
  name    = "gitlab-runner-worker"
  sources = ["source.amazon-ebs.runner"]

  # Boot-time pre-pull service + its script.
  provisioner "file" {
    source      = "${path.root}/files/pull-ci-image.sh"
    destination = "/tmp/pull-ci-image.sh"
  }
  provisioner "file" {
    source      = "${path.root}/files/pull-ci-image.service"
    destination = "/tmp/pull-ci-image.service"
  }

  # Install Docker + tools, bake the CI image, enable the boot service.
  provisioner "shell" {
    environment_vars = [
      "CI_IMAGE=${var.ci_image}",
      "SSH_USER=${var.ssh_username}",
    ]
    script = "${path.root}/scripts/install.sh"
  }
}
