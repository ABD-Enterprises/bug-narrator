output "project_name" {
  value       = local.project_name
  description = "Project name tracked by the Terraform scaffold."
}

output "distribution_model" {
  value       = local.distribution_model
  description = "Current distribution model for BugNarrator."
}

output "environment_descriptions" {
  value       = local.environments
  description = "Human-readable deployment environment descriptions."
}
