provider "exoscale" {
  # NOTE: This is mandatory as Ignition does not support gzipped user data
  gzip_user_data = false
}

provider "aws" {
  region = var.zone

  endpoints {
    s3 = format("https://sos-%s.exo.io", var.zone)
  }

  skip_credentials_validation = true
  skip_get_ec2_platforms      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

resource "aws_s3_bucket" "assets" {
  bucket        = format("%s.%s", var.cluster_name, var.base_domain)
  force_destroy = true

  lifecycle {
    ignore_changes = [object_lock_configuration]
  }
}

module "bootstrap_node" {
  count = var.bootstrap ? 1 : 0

  source = "./modules/bootstrap"

  template_id = var.template_id

  base_domain  = var.base_domain
  cluster_name = var.cluster_name
  zone         = var.zone

  pull_secret = var.pull_secret
  ssh_key     = var.ssh_key

  assets_bucket = aws_s3_bucket.assets.bucket

  wait_for_cluster_cmd = var.wait_for_cluster_cmd
  wait_for_interpreter = var.wait_for_interpreter
}

data "aws_s3_bucket_object" "master_ign" {
  bucket = aws_s3_bucket.assets.id
  key    = "master.ign"

  depends_on = [
    module.bootstrap_node,
  ]
}

data "aws_s3_bucket_object" "kubeconfig" {
  bucket = aws_s3_bucket.assets.id
  key    = "auth/kubeconfig"

  depends_on = [
    module.bootstrap_node,
  ]
}

data "aws_s3_bucket_object" "kubeadmin_password" {
  bucket = aws_s3_bucket.assets.id
  key    = "auth/kubeadmin-password"

  depends_on = [
    module.bootstrap_node,
  ]
}

data "exoscale_domain" "this" {
  name = var.base_domain
}

resource "exoscale_security_group" "master" {
  name = "master-${var.cluster_name}"
}

# TODO: limit access
resource "exoscale_security_group_rules" "master" {
  security_group_id = exoscale_security_group.master.id

  ingress {
    protocol  = "ICMP"
    cidr_list = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "TCP"
    ports     = ["1-65535"]
    cidr_list = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "UDP"
    ports     = ["1-65535"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "null_resource" "wait_for_bootstrap_complete" {
  depends_on = [
    module.bootstrap_node,
  ]

  provisioner "local-exec" {
    command     = var.wait_for_bootstrap_complete_cmd
    interpreter = var.wait_for_interpreter
    environment = {
      ASSETS_BUCKET = aws_s3_bucket.assets.bucket
      ASSETS_DIR    = path.module
      S3_ENDPOINT   = format("https://sos-%s.exo.io", var.zone)
      AWS_REGION    = var.zone
    }
  }
}

resource "exoscale_affinity" "master" {
  name = format("master-%s", var.cluster_name)
  type = "host anti-affinity"
}

resource "exoscale_instance_pool" "master" {
  zone             = var.zone
  name             = format("master-%s", var.cluster_name)
  template_id      = var.template_id
  size             = 3
  service_offering = "extra-large"
  disk_size        = 120
  user_data        = data.aws_s3_bucket_object.master_ign.body

  affinity_group_ids = [
    exoscale_affinity.master.id
  ]

  security_group_ids = [
    exoscale_security_group.master.id,
  ]

  depends_on = [
    module.bootstrap_node,
  ]
}

resource "exoscale_nlb" "master" {
  zone = var.zone
  name = "master-${var.cluster_name}"
}

resource "exoscale_nlb_service" "master_api" {
  nlb_id           = exoscale_nlb.master.id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.master.id
  name             = "master-api-${var.cluster_name}"
  port             = 6443
  target_port      = 6443
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 6443
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "master_machine_config_server" {
  nlb_id           = exoscale_nlb.master.id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.master.id
  name             = "master-machine-config-server-${var.cluster_name}"
  port             = 22623
  target_port      = 22623
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 22623
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_domain_record" "api" {
  domain      = data.exoscale_domain.this.id
  name        = format("api.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_nlb.master.ip_address

  depends_on = [
    null_resource.wait_for_bootstrap_complete,
  ]
}

resource "exoscale_domain_record" "api_int" {
  domain      = data.exoscale_domain.this.id
  name        = format("api-int.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_nlb.master.ip_address

  depends_on = [
    null_resource.wait_for_bootstrap_complete,
  ]
}

resource "exoscale_security_group" "worker" {
  name = "worker-${var.cluster_name}"
}

# TODO: limit access
resource "exoscale_security_group_rules" "worker" {
  security_group_id = exoscale_security_group.worker.id

  ingress {
    protocol  = "ICMP"
    cidr_list = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "TCP"
    ports     = ["1-65535"]
    cidr_list = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "UDP"
    ports     = ["1-65535"]
    cidr_list = ["0.0.0.0/0"]
  }
}

data "aws_s3_bucket_object" "worker_ign" {
  bucket = aws_s3_bucket.assets.id
  key    = "worker.ign"

  depends_on = [
    module.bootstrap_node,
  ]
}

module "worker_group" {
  for_each = var.worker_groups

  source = "./modules/worker_group"

  template_id      = var.template_id
  cluster_name     = var.cluster_name
  zone             = var.zone
  name             = each.key
  size             = each.value.size
  service_offering = each.value.service_offering
  user_data        = data.aws_s3_bucket_object.worker_ign.body
  kubeconfig       = data.aws_s3_bucket_object.kubeconfig.body

  security_group_ids = [
    exoscale_security_group.worker.id,
  ]

  depends_on = [
    null_resource.wait_for_bootstrap_complete,
  ]
}

resource "null_resource" "wait_for_install_complete" {
  depends_on = [
    module.worker_group,
  ]

  provisioner "local-exec" {
    command     = var.wait_for_install_complete_cmd
    interpreter = var.wait_for_interpreter
    environment = {
      ASSETS_BUCKET = aws_s3_bucket.assets.bucket
      ASSETS_DIR    = path.module
      S3_ENDPOINT   = format("https://sos-%s.exo.io", var.zone)
      AWS_REGION    = var.zone
    }
  }
}

resource "exoscale_nlb" "router" {
  zone = var.zone
  name = "router-${var.cluster_name}"
}

resource "exoscale_nlb_service" "router_http" {
  nlb_id           = exoscale_nlb.router.id
  zone             = var.zone
  instance_pool_id = lookup(module.worker_group, var.router_worker_group).this_instance_pool_id
  name             = "router-http-${var.cluster_name}"
  port             = 80
  target_port      = 80
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 80
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "router_https" {
  nlb_id           = exoscale_nlb.router.id
  zone             = var.zone
  instance_pool_id = lookup(module.worker_group, var.router_worker_group).this_instance_pool_id
  name             = "router-https-${var.cluster_name}"
  port             = 443
  target_port      = 443
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 443
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_domain_record" "apps" {
  domain      = data.exoscale_domain.this.id
  name        = format("*.apps.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_nlb.router.ip_address
}
