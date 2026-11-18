variable "namespace" {
  description = "Namespace for the ServiceAccount, Role and RoleBinding."
  type        = string
}

variable "service_account_name" {
  description = "Name of the ServiceAccount used by the workloads."
  type        = string
  default     = "bituach-app"
}

variable "role_name" {
  description = "Name of the Role bound to the ServiceAccount."
  type        = string
  default     = "bituach-app-role"
}

variable "role_rules" {
  description = "RBAC rules granted to the ServiceAccount inside the namespace."
  type = list(object({
    api_groups = list(string)
    resources  = list(string)
    verbs      = list(string)
  }))
  default = []
}

variable "additional_subjects" {
  description = "Extra subjects bound to the same Role (e.g. a human group or the Argo CD service account)."
  type = list(object({
    kind      = string
    name      = string
    namespace = optional(string)
  }))
  default = []
}
