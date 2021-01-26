locals {
  assets_dir = "${path.module}/${var.cluster_name}"

  install_config_yaml = templatefile("${path.module}/install-config.tmpl.yaml",
    {
      base_domain  = var.base_domain
      cluster_name = var.cluster_name
      pull_secret  = var.pull_secret
      ssh_key      = var.ssh_key
    }
  )
}

data "exoscale_domain" "this" {
  name = var.base_domain
}

resource "aws_s3_bucket_object" "install_config" {
  bucket  = var.assets_bucket
  key     = "install-config.yaml"
  content = local.install_config_yaml
  etag    = md5(local.install_config_yaml)
}

resource "null_resource" "generate_assets" {
  provisioner "local-exec" {
    command     = var.sync_assets_bucket
    interpreter = var.wait_for_interpreter
    environment = {
      ASSETS_BUCKET = var.assets_bucket
      ASSETS_DIR    = local.assets_dir
      S3_ENDPOINT   = format("https://sos-%s.exo.io", var.zone)
      AWS_REGION    = var.zone
    }
  }

  provisioner "local-exec" {
    command = "openshift-install create manifests --dir=${local.assets_dir}"
  }

  provisioner "local-exec" {
    command = "sed -i -E 's/mastersSchedulable(.) true/mastersSchedulable\\1 false/' ${local.assets_dir}/manifests/cluster-scheduler-02-config.yml"
  }

  provisioner "local-exec" {
    command = "openshift-install create ignition-configs --dir=${local.assets_dir}"
  }

  provisioner "local-exec" {
    command = format("aws s3 --endpoint https://sos-%s.exo.io sync %s s3://%s --content-type text/plain", var.zone, local.assets_dir, var.assets_bucket)

    environment = {
      AWS_REGION = var.zone
    }
  }
}

resource "exoscale_security_group" "bootstrap" {
  name = "bootstrap-${var.cluster_name}"
}

# TODO: limit access
resource "exoscale_security_group_rules" "bootstrap" {
  security_group_id = exoscale_security_group.bootstrap.id

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

data "external" "presign" {
  program = ["sh", "${path.module}/s3_presign.sh"]

  query = {
    endpoint = "https://sos-${var.zone}.exo.io"
    s3uri    = format("s3://%s/bootstrap.ign", var.assets_bucket)
  }

  depends_on = [
    null_resource.generate_assets,
  ]
}

data "ignition_config" "bootstrap" {
  replace {
    source = data.external.presign.result.presign
  }
}

resource "exoscale_compute" "bootstrap" {
  zone        = var.zone
  template_id = var.template_id
  size        = "Extra-large"
  disk_size   = 120
  hostname    = "bootstrap-${var.cluster_name}"
  reverse_dns = format("bootstrap.%s.%s.", var.cluster_name, var.base_domain)
  user_data   = data.ignition_config.bootstrap.rendered

  security_group_ids = [
    exoscale_security_group.bootstrap.id,
  ]

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}

resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command     = var.wait_for_cluster_cmd
    interpreter = var.wait_for_interpreter
    environment = {
      ENDPOINT = format("https://%s:6443", exoscale_compute.bootstrap.ip_address)
    }
  }
}

resource "exoscale_domain_record" "bootstrap" {
  domain      = data.exoscale_domain.this.id
  name        = format("bootstrap.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_compute.bootstrap.ip_address
}

resource "exoscale_domain_record" "api" {
  domain      = data.exoscale_domain.this.id
  name        = format("api.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_compute.bootstrap.ip_address
}

resource "exoscale_domain_record" "api_int" {
  domain      = data.exoscale_domain.this.id
  name        = format("api-int.%s", var.cluster_name)
  record_type = "A"
  ttl         = 300
  content     = exoscale_compute.bootstrap.ip_address
}
