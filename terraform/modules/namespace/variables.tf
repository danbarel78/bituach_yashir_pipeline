variable "name" {
  description = "Namespace name, e.g. bituach-dev."
  type        = string
}

variable "environment" {
  description = "Environment label applied to the namespace (dev/staging/prod)."
  type        = string
}

variable "labels" {
  description = "Additional labels to apply to the namespace."
  type        = map(string)
  default     = {}
}

variable "pod_security_enforce" {
  description = "Pod Security Admission level to enforce (privileged/baseline/restricted)."
  type        = string
  default     = "baseline"
}
