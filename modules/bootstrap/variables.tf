variable "template_id" {
  description = "The ID of the Compute template to use."
  type        = string
}

variable "base_domain" {
  description = "The base domain used for Ingresses."
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

variable "artifacts_bucket" {
  type = string
}

variable "pull_secret" {
  type = string
}

variable "ssh_key" {
  type = string
}

variable "wait_for_cluster_cmd" {
  description = "Custom local-exec command to execute for determining if the opesnhift cluster is healthy. Cluster endpoint will be available as an environment variable called ENDPOINT"
  type        = string
}

variable "wait_for_interpreter" {
  description = "Custom local-exec command line interpreter for the command to determining if the eks cluster is healthy."
  type        = list(string)
}
