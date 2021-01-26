resource "exoscale_affinity" "this" {
  name = format("%s-%s", var.name, var.cluster_name)
  type = "host anti-affinity"
}

resource "exoscale_instance_pool" "this" {
  zone               = var.zone
  name               = format("%s-%s", var.name, var.cluster_name)
  template_id        = var.template_id
  size               = var.size
  service_offering   = var.service_offering
  disk_size          = 120
  user_data          = var.user_data
  affinity_group_ids = [exoscale_affinity.this.id]
  security_group_ids = var.security_group_ids
}

resource "null_resource" "approve_node_bootstrapper_csr" {
  count = exoscale_instance_pool.this.size

  provisioner "local-exec" {
    command     = <<EOT
for _ in $(seq 1 60); do
  for csr in $(KUBECONFIG=<(echo "${var.kubeconfig}") oc get csr -o go-template='{{range .items}}{{if eq .spec.username "system:serviceaccount:openshift-machine-config-operator:node-bootstrapper"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'); do
    request=$(KUBECONFIG=<(echo "${var.kubeconfig}") oc get csr $csr -o go-template='{{.spec.request}}')
    subject=$(echo "$request" | base64 -d | openssl req -noout -subject)
    if [ "$subject" = "subject=O = system:nodes, CN = system:node:${tolist(exoscale_instance_pool.this.virtual_machines)[count.index]}" ]; then
      KUBECONFIG=<(echo "${var.kubeconfig}") oc adm certificate approve "$csr"
      exit 0
    fi
  done
  sleep 5
done
echo TIMEOUT
exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    command     = <<EOT
for _ in $(seq 1 60); do
  for csr in $(KUBECONFIG=<(echo "${var.kubeconfig}") oc get csr -o go-template='{{range .items}}{{if eq .spec.username "system:node:${tolist(exoscale_instance_pool.this.virtual_machines)[count.index]}"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'); do
    KUBECONFIG=<(echo "${var.kubeconfig}") oc adm certificate approve "$csr"
    exit 0
  done
  sleep 5
done
echo TIMEOUT
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
