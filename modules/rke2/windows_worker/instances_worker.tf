resource "aws_instance" "windows_worker" {
  depends_on = [
    var.dependency
  ]
  ami                    = var.aws_ami
  instance_type          = var.ec2_instance_class
  count                  = var.no_of_worker_nodes
  iam_instance_profile   = "${var.iam_role}"
  get_password_data      = true
  user_data              = templatefile("../install/join_rke2_windows_agent.tftpl", {serverIP: "${local.master_ip}", token: "${local.node_token}", install_mode: "${var.install_mode}", rke2_version: "${var.rke2_version}"})
  subnet_id              = var.subnets
  availability_zone      = var.availability_zone
  vpc_security_group_ids = ["${var.sg_id}"]
  key_name               = var.key_name
  tags = {
    Name                 = "${var.resource_name}-${local.resource_tag}-windows-worker-${count.index + 1}"
    Team                 = local.resource_tag
    "kubernetes.io/cluster/clusterid" = "owned"
  }
}

data "local_file" "master_ip" {
  depends_on = [var.dependency]
  filename = "/tmp/${var.resource_name}_master_ip"
}

locals {
  master_ip    = trimspace("${data.local_file.master_ip.content}")
  resource_tag = "distros-qa"
}

data "local_file" "token" {
  depends_on = [var.dependency]
  filename = "/tmp/${var.resource_name}_nodetoken"
}

locals {
  node_token = trimspace("${data.local_file.token.content}")
}
