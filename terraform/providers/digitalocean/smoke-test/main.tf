terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
  }
}

provider "digitalocean" {}

resource "digitalocean_tag" "opsorchestra" {
  name = "opsorchestra-smoke-test"
}

resource "digitalocean_droplet" "smoke_test" {
  name   = var.droplet_name
  region = var.region
  size   = var.size
  image  = var.image

  tags = [
    digitalocean_tag.opsorchestra.id
  ]

  # This disposable provisioning test holds no workload data. Delete directly
  # rather than waiting for the guest OS to acknowledge a shutdown request.
  graceful_shutdown = false

  # Allow extra time for provider operations such as waiting for an unlocked Droplet.
  timeouts {
    delete = "5m"
  }
}
