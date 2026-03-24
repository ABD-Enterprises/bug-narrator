terraform {
  required_version = ">= 1.6.0"
}

locals {
  project_name       = var.project_name
  distribution_model = "github-releases"
  environments = {
    dev  = "local development and branch validation"
    test = "manual release-candidate validation"
    prod = "public GitHub Releases distribution"
  }
}
