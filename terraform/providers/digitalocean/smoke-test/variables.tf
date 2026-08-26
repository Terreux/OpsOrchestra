variable "droplet_name" {
  description = "Name of the temporary OpsOrchestra smoke-test Droplet"
  type        = string
  default     = "opsorchestra-smoke-test"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sfo3"
}

variable "size" {
  description = "DigitalOcean Droplet size"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "image" {
  description = "DigitalOcean Droplet image"
  type        = string
  default     = "ubuntu-24-04-x64"
}