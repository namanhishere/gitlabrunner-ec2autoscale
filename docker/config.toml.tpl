concurrent = ${CONCURRENT}
check_interval = 0
log_level = "info"

[session_server]
  session_timeout = 1800

[[runners]]
  name = "docker-autoscaler-ec2"
  url = "${CI_SERVER_URL}"
  token = "${RUNNER_TOKEN}"
  executor = "docker-autoscaler"

  # Docker image/settings used to run each job on the target EC2 instance.
  # Defaults to the CI image pre-baked/pre-pulled into the AMI so cold starts
  # skip the pull. Jobs can still override `image:` in .gitlab-ci.yml.
  [runners.docker]
    image = "${CI_IMAGE}"
    privileged = false
    volumes = ["/cache"]

  [runners.autoscaler]
    # Fleeting plugin that talks to AWS Auto Scaling. Installed at container
    # startup by entrypoint.sh via `gitlab-runner fleeting install`.
    plugin = "aws:latest"

    # One job per instance, instance discarded afterwards -> clean, isolated builds.
    capacity_per_instance = 1
    max_use_count = 1
    max_instances = ${MAX_INSTANCES}

    [runners.autoscaler.plugin_config]
      name   = "${ASG_NAME}"   # AWS Auto Scaling Group name
      region = "${AWS_REGION}"

    [runners.autoscaler.connector_config]
      username          = "${SSH_USER}"
      key_path          = "/home/gitlab-runner/.ssh/ec2-key.pem"
      use_external_addr = true   # SSH to the instance's public IP

    [[runners.autoscaler.policy]]
      idle_count = ${IDLE_COUNT}
      idle_time  = "${IDLE_TIME}"
