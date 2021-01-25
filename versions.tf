terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.24"
    }
    exoscale = {
      source  = "exoscale/exoscale"
      version = "~> 0.21"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "~> 2.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.6"
    }
  }
  required_version = ">= 0.13"
}
