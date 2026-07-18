# GitLab Runner → EC2 autoscaler

A self-contained, Dockerized **GitLab Runner manager** that autoscales CI jobs onto
**ephemeral EC2 instances**, using the **Docker Autoscaler** executor and the
**`fleeting-plugin-aws`** plugin backed by an **AWS Auto Scaling Group (ASG)**.

The manager runs in a container via `docker compose`. When jobs are queued it scales the
ASG up, SSHes into each fresh EC2 instance, runs the job in a Docker container there, then
scales back down. Instances boot from a **custom AMI** (built with Packer) that has Docker,
tooling, and the **CI image** pre-baked, so cold starts are fast. The CI image itself is
built and published to **GHCR** by GitHub Actions.



## Repository layout

```
.
├── docker-compose.yml            # toolbox + runner services (run from repo root)
├── .env.example                  # copy to .env
├── .github/workflows/
│   ├── build-ci-image.yml        # build + push the CI image to GHCR
│   └── validate.yml              # terraform/packer/shell checks on PRs
├── ci-image/
│   └── Dockerfile                # the image CI jobs run in (published to GHCR)
├── toolbox/
│   └── Dockerfile                # dev container: aws-cli, terraform, packer, git
├── packer/                       # builds the custom worker AMI
│   ├── gitlab-runner.pkr.hcl
│   ├── scripts/install.sh        # installs Docker + tools, bakes the CI image
│   └── files/                    # boot-time CI-image refresh (systemd)
├── docker/
│   ├── entrypoint.sh             # installs the fleeting plugin + renders config
│   └── config.toml.tpl           # runner config template (envsubst)
└── terraform/                    # AWS infra: ASG, launch template, IAM, SG, key pair
```

## How the pieces fit

- **CI image** (`ci-image/`) — the container your jobs run in. GitHub Actions builds it and
  pushes `ghcr.io/<owner>/<repo>-ci:latest`.
- **Worker AMI** (`packer/`) — Amazon Linux 2023 with Docker + tools preinstalled and the CI
  image baked in. A systemd unit refreshes the image to `:latest` on every boot.
- **Infra** (`terraform/`) — the ASG (min/desired 0), launch template (uses the custom AMI),
  security group, SSH key pair, and a least-privilege IAM user for the plugin.
- **Runner manager** (`docker-compose.yml` → `runner`) — long-running container that talks to
  GitLab and drives the ASG.
- **Toolbox** (`docker-compose.yml` → `toolbox`) — throwaway dev container with AWS CLI,
  Terraform, and Packer, so you don't install any of them on the host. It uses your
  **mounted `~/.aws`** credentials, keeping credential handling in one place.

## Prerequisites

- **Docker + Docker Compose v2** on the host (nothing else — the toolbox provides aws-cli,
  Terraform, and Packer).
- AWS credentials in **`~/.aws`** with permission to build AMIs and create EC2/ASG/IAM.
  (Run `mkdir -p ~/.aws` first; you can `aws configure` from inside the toolbox.)
- A **GitHub** repo (for the CI image + GHCR) and a **self-managed GitLab** instance.

---

## Step 1 — Build & publish the CI image (GHCR)

1. Edit `ci-image/Dockerfile` to install whatever your pipelines need, and set the
   `org.opencontainers.image.source` label to your repo URL.
2. Push to GitHub. The **Build & publish CI image** workflow runs on changes to `ci-image/**`
   (and on tags, weekly, or manually via *Actions → Run workflow*).
3. It publishes `ghcr.io/<owner>/<repo>-ci` with tags `latest`, `sha-<short>`, and any `vX.Y.Z`
   tag. Confirm under **your repo → Packages**.
4. **Make the package public** (Package → *Package settings* → *Change visibility → Public*),
   since the AMI pulls it without authentication.

The full reference you'll use below is `ghcr.io/<owner>/<repo>-ci:latest`.

## Step 2 — Bootstrap the toolbox

All AMI/Terraform work runs inside the toolbox container:

```bash
docker compose build toolbox
docker compose run --rm toolbox        # opens an interactive shell in /workspace
```

Inside the toolbox, `/workspace` is this repo and `~/.aws` is mounted, so `aws`, `terraform`,
and `packer` all use your credentials. Check access:

```bash
aws sts get-caller-identity
# If you use SSO/profiles:  AWS_PROFILE=myprofile docker compose run --rm toolbox
```

Everything below is run **inside the toolbox** unless noted.

## Step 3 — Build the custom AMI (Packer)

```bash
cd packer
cp gitlab-runner.pkrvars.hcl.example gitlab-runner.pkrvars.hcl
# Set ci_image to ghcr.io/<owner>/<repo>-ci:latest and region.
packer init .
packer build -var-file=gitlab-runner.pkrvars.hcl .
```

Packer prints the new AMI id. Terraform finds it automatically by name prefix
(`ami_name_prefix`, default `gitlab-runner-ec2autoscale`), or you can pin `ami_id`.

## Step 4 — Provision AWS infrastructure (Terraform)

```bash
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
# Set manager_cidr to this host's public IP as /32:  curl -s https://checkip.amazonaws.com
terraform init
terraform apply
```

Export the outputs the runner needs (still in the toolbox — paths land on the host repo):

```bash
mkdir -p ../secrets
terraform output -raw private_key_pem > ../secrets/ec2-key.pem
chmod 600 ../secrets/ec2-key.pem

terraform output asg_name
terraform output access_key_id
terraform output -raw secret_access_key
```

Exit the toolbox (`exit`) when done.

## Step 5 — Start the GitLab Runner manager

1. In GitLab (**Admin / Group / Project → CI/CD → Runners → New runner**) create a runner and
   copy the **authentication token** (`glrt-…`).
2. Configure `.env` (on the host, repo root):

   ```bash
   cp .env.example .env
   ```

   Set:
   - `CI_SERVER_URL` – your GitLab base URL.
   - `RUNNER_TOKEN` – the `glrt-…` token.
   - `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `ASG_NAME` – from Terraform.
   - `CI_IMAGE` – `ghcr.io/<owner>/<repo>-ci:latest` (same image baked into the AMI).
   - Tune `MAX_INSTANCES` (≤ Terraform `max_instances`), `CONCURRENT`, `IDLE_COUNT`, `IDLE_TIME`.

   Ensure `secrets/ec2-key.pem` exists (Step 4).

3. Start it:

   ```bash
   docker compose up -d runner
   docker compose logs -f runner
   ```

The fleeting plugin installs, the runner starts, and it appears **online** in GitLab.

## Verify it autoscales

Run a CI job on the runner, then watch the ASG (from the toolbox, or any host with aws-cli):

```bash
watch -n5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <asg_name> --region <region> \
  --query "AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[].LifecycleState}"'
```

Desired capacity goes `0 → 1`, an instance launches, the (pre-pulled) CI image runs the job,
and with `max_use_count=1` the instance is discarded afterward.

---

## Maintenance & updates

| Change | What to do |
| --- | --- |
| **Update CI image contents** | Edit `ci-image/Dockerfile`, push → Actions rebuilds `:latest`. New instances pull the refreshed image on boot. To bake it in, rebuild the AMI (below). |
| **Update baked AMI** (new CI image / tooling / base patches) | In the toolbox: `packer build` a new AMI, then `terraform apply` — the launch template picks up the newest AMI by prefix. Existing instances are ephemeral and get replaced per job. |
| **Change scaling / runner config** | Edit `.env`, then `docker compose up -d runner` (config is regenerated from `config.toml.tpl` on start). |
| **Upgrade the runner image** | `docker compose pull runner && docker compose up -d runner`. |
| **Upgrade toolbox tooling** | Bump `TERRAFORM_VERSION` / `PACKER_VERSION` in `toolbox/Dockerfile`, then `docker compose build toolbox`. |
| **Tear everything down** | `docker compose down`; in the toolbox `cd terraform && terraform destroy`; optionally deregister old AMIs. |

Common operations:

| Action | Command (repo root) |
| --- | --- |
| Toolbox shell | `docker compose run --rm toolbox` |
| One-off toolbox command | `docker compose run --rm toolbox -c "cd terraform && terraform plan"` |
| Runner logs | `docker compose logs -f runner` |
| Restart runner | `docker compose up -d runner` |
| Stop runner | `docker compose down` |

## Notes & hardening

- **Credential isolation:** the toolbox mounts `~/.aws` (your admin creds) and is used only for
  build/provision. The long-running `runner` uses the **separate least-privilege IAM user**
  Terraform creates (autoscaling + `ec2:DescribeInstances` only). Keep the two separate.
- **CI image visibility:** the AMI pulls the image unauthenticated, so the GHCR package must be
  **public**. For a private image you'd add `docker login ghcr.io` (with a token) to the boot
  service — out of scope here.
- **Networking:** instances get public IPs and are reached over SSH (`use_external_addr=true`).
  For production, use private subnets + NAT or an SSM-based connector, and tighten `manager_cidr`.
- **Ephemeral jobs:** `capacity_per_instance=1` + `max_use_count=1` gives one clean instance per
  job. Raise `capacity_per_instance` / `idle_count` to trade isolation for cost/latency.
- **Pinning:** `gitlab/gitlab-runner:latest` and the AL2023 base float to newest; pin them (and
  a specific AMI via `ami_id`) for reproducible production deployments.
- **Secrets:** `.env`, `secrets/`, `*.pem`, `*.pkrvars.hcl`, and Terraform state are git-ignored.
