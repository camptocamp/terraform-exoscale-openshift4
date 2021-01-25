variable "template_id" {
  description = "The ID of the Compute template to use."
  type        = string
}

variable "cluster_name" {
  description = "The name of the Kubernetes cluster to create."
  type        = string
}

variable "zone" {
  description = "The name of the zone to deploy the cluster into."
  type        = string
}

variable "name" {
  description = "The name of the worker group."
  type        = string
}

variable "size" {
  description = "The number of Compute instance members the Instance Pool manages."
  type        = number
}

variable "service_offering" {
  description = "The managed Compute instances size."
  type        = string
}

variable "user_data" {
  description = "An ignition configuration to apply when creating Compute instances."
  type        = string
}

variable "security_group_ids" {
  description = "A list of Security Group IDs."
  type        = list(any)
}

variable "kubeconfig" {
  description = "Path to the KUBECONFIG file."
  type        = string
}
