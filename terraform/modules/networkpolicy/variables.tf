variable "namespace" {
  description = "Namespace the policies apply to."
  type        = string
}

variable "app_selector" {
  description = "Label selector identifying this environment's application pods."
  type        = map(string)
  default     = { "app.kubernetes.io/part-of" = "bituach-yashir" }
}

variable "ingress_namespace" {
  description = "Namespace of the ingress controller allowed to reach the app pods."
  type        = string
  default     = "ingress-nginx"
}

variable "allow_internet_egress" {
  description = "Allow egress outside the cluster. Dev/staging need it for registry pulls; prod should not."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Prefix for generated policy names."
  type        = string
  default     = "bituach"
}
