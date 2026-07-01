variable "github_repo" {
  description = "owner/repo this runner registers against"
  type        = string
  default     = "windsornguyen/github-actions-on-dms"
}

variable "runner_name" {
  description = "self-hosted runner display name"
  type        = string
  default     = "dm-runner-1"
}

variable "runner_version" {
  description = "actions/runner release version to install"
  type        = string
  default     = "2.335.1"
}
