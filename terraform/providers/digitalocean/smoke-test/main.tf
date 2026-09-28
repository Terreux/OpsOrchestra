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

  graceful_shutdown = true

  # The provider defaults to 60 seconds, which can expire during guest shutdown.
  timeouts {
    delete = "5m"
  }
}
