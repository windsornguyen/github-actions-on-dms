terraform {
  required_version = ">= 1.5"

  required_providers {
    dedalus = {
      source  = "dedalus-labs/dedalus"
      version = "~> 0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Reads DEDALUS_API_KEY / DEDALUS_BASE_URL from the environment. Only
# dev.dcs.dedaluslabs.ai is reachable with the key used for this demo;
# prod does not work with it.
provider "dedalus" {}
