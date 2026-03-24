variable "project_name" {
  description = "Project name for future distribution infrastructure."
  type        = string
  default     = "BugNarrator"
}

variable "release_bucket_name" {
  description = "Optional future artifact bucket or storage target name."
  type        = string
  default     = null
}

variable "docs_site_domain" {
  description = "Optional future public docs-site domain."
  type        = string
  default     = null
}
