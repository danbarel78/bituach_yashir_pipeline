variable "namespace" {
  description = "Namespace of the target Deployment."
  type        = string
}

variable "name" {
  description = "Name of the HPA, normally <service>-hpa."
  type        = string
}

variable "deployment_name" {
  description = "Deployment (or StatefulSet) to scale."
  type        = string
}

variable "api_version" {
  description = "apiVersion of the scale target."
  type        = string
  default     = "apps/v1"
}

variable "target_kind" {
  description = "Kind of the scale target."
  type        = string
  default     = "Deployment"
}

variable "min_replicas" {
  description = "Lower replica bound."
  type        = number
}

variable "max_replicas" {
  description = "Upper replica bound. Kept small: this is a single-node cluster."
  type        = number
}

variable "cpu_utilization" {
  description = "Target average CPU utilisation percentage."
  type        = number
  default     = 70
}
