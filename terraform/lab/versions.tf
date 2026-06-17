terraform {
  required_version = ">= 1.8.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.50.0, < 3.0.0"
    }
  }
  # Local state on purpose: this lab is disposable and must not touch the
  # scaleway-lab project's shared S3 state.
}

provider "scaleway" {}
