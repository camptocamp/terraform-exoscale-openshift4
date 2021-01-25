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

variable "bootstrap" {
  type = bool
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
  default     = "for i in `seq 1 60`; do if `command -v wget > /dev/null`; then wget --no-check-certificate -O - -q $ENDPOINT/readyz >/dev/null && exit 0 || true; else curl -k -s $ENDPOINT/readyz >/dev/null && exit 0 || true;fi; sleep 5; done; echo TIMEOUT && exit 1"
}

variable "wait_for_bootstrap_complete_cmd" {
  description = "Custom local-exec command to execute for determining if the bootstrap of the openshift cluster is complete. Artifacts dir will be available as an environment variable called ARTIFACTS_DIR"
  type        = string
  default     = "openshift-install --dir=$ARTIFACTS_DIR wait-for bootstrap-complete"
}

variable "wait_for_install_complete_cmd" {
  description = "Custom local-exec command to execute for determining if the installation of the openshift cluster is complete. Artifacts dir will be available as an environment variable called ARTIFACTS_DIR"
  type        = string
  default     = "openshift-install --dir=$ARTIFACTS_DIR wait-for install-complete"
}

variable "wait_for_interpreter" {
  description = "Custom local-exec command line interpreter for the command to determining if the eks cluster is healthy."
  type        = list(string)
  default     = ["/bin/sh", "-c"]
}

variable "worker_groups" {
  description = "The worker groups to create."
  type        = map(any)
  default = {
    "router" = {
      size             = 2
      service_offering = "large"
    }
  }
}

variable "router_worker_group" {
  default = "router"
}
