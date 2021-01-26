locals {
  assets_dir = "${path.module}/${var.cluster_name}"
}

data "exoscale_domain" "this" {
  name = var.base_domain
}

resource "null_resource" "get_assets" {
  provisioner "local-exec" {
    command = format("aws s3 --endpoint https://sos-%s.exo.io --region %s sync s3://%s %s", var.zone, var.zone, var.assets_bucket, local.assets_dir)
  }
}

resource "local_file" "install_config_yaml" {
  filename = "${local.assets_dir}/install-config.yaml"
  content = templatefile("${path.module}/install-config.tmpl.yaml",
    {
      base_domain  = var.base_domain
      cluster_name = var.cluster_name
      pull_secret  = var.pull_secret
      ssh_key      = var.ssh_key
    }
  )

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
    command = format("aws s3 --endpoint https://sos-%s.exo.io --region %s sync %s s3://%s --content-type text/plain", var.zone, var.zone, local.assets_dir, var.assets_bucket)
  }

  depends_on = [
    null_resource.get_assets,
  ]
}

data "null_data_source" "ugly_hack" {
  inputs = {
    assets_dir = dirname(local_file.install_config_yaml.filename)
    content    = local_file.install_config_yaml.content
  }

  depends_on = [
    local_file.install_config_yaml,
  ]
}

data "null_data_source" "assets" {
  inputs = {
    bootstrap_ign = file("${data.null_data_source.ugly_hack.outputs.assets_dir}/bootstrap.ign")
    master_ign    = file("${data.null_data_source.ugly_hack.outputs.assets_dir}/master.ign")
    worker_ign    = file("${data.null_data_source.ugly_hack.outputs.assets_dir}/worker.ign")
  }

  depends_on = [
    local_file.install_config_yaml,
  ]
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
