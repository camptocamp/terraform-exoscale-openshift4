terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = "~> 0.21"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "~> 2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    null = {
      source = "hashicorp/null"
      vesion = "~> 3.0"
    }
  }
  required_version = ">= 0.13"
}
