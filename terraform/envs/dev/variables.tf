variable "kubeconfig_path" {
  description = "Path to the kubeconfig used by the kubernetes provider."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to target."
  type        = string
  default     = "docker-desktop"
}
