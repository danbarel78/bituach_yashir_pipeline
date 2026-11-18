variable "namespace" {
  description = "Namespace that receives the quota and limit range."
  type        = string
}

variable "quota_pods" {
  description = "Hard limit on the number of pods in the namespace."
  type        = string
}

variable "quota_cpu" {
  description = "Hard CPU limit for the namespace, e.g. \"2\"."
  type        = string
}

variable "quota_memory" {
  description = "Hard memory limit for the namespace, e.g. \"2Gi\"."
  type        = string
}

variable "default_request_cpu" {
  description = "Default CPU request injected when a container omits one."
  type        = string
}

variable "default_request_memory" {
  description = "Default memory request injected when a container omits one."
  type        = string
}

variable "default_limit_cpu" {
  description = "Default CPU limit injected when a container omits one."
  type        = string
}

variable "default_limit_memory" {
  description = "Default memory limit injected when a container omits one."
  type        = string
}

variable "max_limit_cpu" {
  description = "Maximum CPU limit a single container may request."
  type        = string
}

variable "max_limit_memory" {
  description = "Maximum memory limit a single container may request."
  type        = string
}
