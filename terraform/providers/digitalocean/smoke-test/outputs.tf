output "droplet_id" {
  value = digitalocean_droplet.smoke_test.id
}

output "droplet_name" {
  value = digitalocean_droplet.smoke_test.name
}

output "ipv4_address" {
  value = digitalocean_droplet.smoke_test.ipv4_address
}

output "status" {
  value = digitalocean_droplet.smoke_test.status
}

output "hourly_price" {
  value = digitalocean_droplet.smoke_test.price_hourly
}