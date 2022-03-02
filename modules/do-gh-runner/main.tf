terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Define which region to use
# https://docs.digitalocean.com/products/platform/availability-matrix/#available-datacenters
variable "region" {
  type    = string
  default = "nyc1"
}

# SSH key fingerprint to admin the runner
variable "ssh_key" {
  type = string
}

# Name of the runner
variable "runner_name" {
  type    = string
  default = null
}

# Runner registration repo/org
variable "runner_scope" {
  type = string
}

# Runner registration token
# gh api -p everest -X POST repos/{owner}/{repo}/actions/runners/registration-token | jq .token
variable "runner_token" {
  type = string
}

# Get the cheapest droplet
data "digitalocean_sizes" "main" {
  filter {
    key    = "available"
    values = [true]
  }
  filter {
    key    = "regions"
    values = [var.region]
  }
  sort {
    key       = "price_monthly"
    direction = "asc"
  }
}

# Get the latest Ubuntu
data "digitalocean_images" "ubuntu" {
  filter {
    key    = "distribution"
    values = ["Ubuntu"]
  }
  filter {
    key      = "description"
    values   = ["^Ubuntu .* x64$"]
    match_by = "re"
  }
  filter {
    key    = "regions"
    values = [var.region]
  }
  sort {
    key       = "created"
    direction = "desc"
  }
}

locals {
  runner_name = var.runner_name != null ? var.runner_name : format("do-%s-gh-runner", replace(var.runner_scope, "/", "-"))
}

# Create a GitHub runner
resource "digitalocean_droplet" "github_runner" {
  image      = data.digitalocean_images.ubuntu.images[0].slug
  name       = local.runner_name
  region     = var.region
  size       = data.digitalocean_sizes.main.sizes[0].slug
  monitoring = true // Free
  ipv6       = true // Free
  ssh_keys   = [var.ssh_key]
  user_data  = <<-EOF
  #cloud-config
  users:
    - name: runner
      groups: sudo
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
  runcmd:
    - [su, runner, -c, "mkdir ~/actions-runner"]
    - [su, runner, -c, "curl -o ~/actions-runner/actions-runner-linux-x64-2.287.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.287.1/actions-runner-linux-x64-2.287.1.tar.gz"]
    - [su, runner, -c, "tar xzf ~/actions-runner/actions-runner-linux-x64-2.287.1.tar.gz -C ~/actions-runner"]
    - [su, runner, -c, "~/actions-runner/config.sh --unattended --url https://github.com/${var.runner_scope} --token ${var.runner_token}"]
    - cd /home/runner/actions-runner
    - ./svc.sh install
    - ./svc.sh start
  EOF
}

output "ips" {
  description = "Github runner IP addresses (ipv4 & ipv6)"
  value = {
    ipv4 = digitalocean_droplet.github_runner.ipv4_address
    ipv6 = digitalocean_droplet.github_runner.ipv6_address
  }
}
