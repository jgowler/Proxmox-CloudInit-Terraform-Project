terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_user             = var.pm_user
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}

# Local variables

locals {
  starting_vmid     = 400
  base_ip_parts     = split(".", var.base_ip)
  base_ip_last      = tonumber(local.base_ip_parts[3])
  ip_prefix         = "${local.base_ip_parts[0]}.${local.base_ip_parts[1]}.${local.base_ip_parts[2]}"
  ansible_ip        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + var.worker_count + 1}"
  combined_ssh_keys = join("\n", [file(var.ssh_pub_key), file(var.ansible_public_key)])
}

# Create VMs

resource "proxmox_vm_qemu" "kubernetes_master" {
  count       = var.master_count
  target_node = "homelab"

  name        = "KubernetesMaster${count.index + 1}"
  vmid        = local.starting_vmid + count.index
  clone       = "ubuntu-cloud"
  agent       = 1
  description = "Kubernetes Master node deployed using Terraform."

  memory     = 2048
  full_clone = true
  scsihw     = "virtio-scsi-single"
  os_type    = "cloud-init"
  boot       = "order=scsi0"

  ciuser     = "root"
  sshkeys    = local.combined_ssh_keys
  ipconfig0  = "ip=${local.ip_prefix}.${local.base_ip_last + count.index}/24,gw=${var.gateway_address}"
  nameserver = "8.8.8.8"
  skip_ipv6  = true


  serial {
    id   = 0
    type = "socket"
  }

  cpu {
    cores   = 2
    sockets = 1
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size       = "32G"
          storage    = "local-lvm"
          replicate  = true
          discard    = true
          emulatessd = true
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  connection {
    type        = "ssh"
    host        = "${local.ip_prefix}.${local.base_ip_last + count.index}"
    user        = "root"
    private_key = file(var.ssh_private_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get upgrade -y -o Dpkg::Options::='--force-confold'",
      "apt-get install -y qemu-guest-agent python3 python3-pip",
      "sleep 10",
      "systemctl enable --now qemu-guest-agent"
    ]
  }
}


# Worker node config

resource "proxmox_vm_qemu" "kubernetes_worker" {
  count       = var.worker_count
  target_node = "homelab"

  name        = "KubernetesWorker${count.index + 1}"
  vmid        = local.starting_vmid + var.master_count + count.index
  clone       = "ubuntu-cloud"
  agent       = 1
  description = "Kubernetes Worker node deployed using Terraform."

  memory     = 4096
  full_clone = true
  scsihw     = "virtio-scsi-single"
  os_type    = "cloud-init"
  boot       = "order=scsi0"

  ciuser     = "root"
  sshkeys    = local.combined_ssh_keys
  ipconfig0  = "ip=${local.ip_prefix}.${local.base_ip_last + var.master_count + count.index}/24,gw=${var.gateway_address}"
  nameserver = "8.8.8.8"
  ciupgrade  = true
  skip_ipv6  = true


  serial {
    id   = 0
    type = "socket"
  }

  cpu {
    cores   = 2
    sockets = 1
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size       = "32G"
          storage    = "local-lvm"
          replicate  = true
          discard    = true
          emulatessd = true
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  connection {
    type        = "ssh"
    host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + count.index}"
    user        = "root"
    private_key = file(var.ssh_private_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get upgrade -y -o Dpkg::Options::='--force-confold'",
      "apt-get install -y qemu-guest-agent python3 python3-pip",
      "sleep 10",
      "systemctl enable --now qemu-guest-agent"
    ]
  }
}

resource "proxmox_lxc" "ansible" {
  target_node  = "homelab"
  hostname     = "Ansible"
  vmid         = local.starting_vmid + var.master_count + var.worker_count + 1
  ostemplate   = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  unprivileged = true
  cores        = 1
  memory       = 2048
  nameserver   = "8.8.8.8"
  start        = true

  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }

  cmode = "tty"
  tty   = 2

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${local.ip_prefix}.${local.base_ip_last + var.master_count + var.worker_count + 1}/24"
    gw     = var.gateway_address
  }


  ssh_public_keys = file(var.ssh_pub_key)

  connection {
    type        = "ssh"
    host        = local.ansible_ip
    user        = "root"
    private_key = file(var.ssh_private_key)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "apt update -y && apt upgrade -y",
      "apt install -y qemu-guest-agent openssh-server python3 python3-pip software-properties-common",
      "systemctl start --now qemu-guest-agent",
      "systemctl enable --now ssh",
      "add-apt-repository --yes --update ppa:ansible/ansible",
      "apt update -y && apt install -y ansible"
    ]

  }
}

resource "null_resource" "copy_ansible_private_key" {

  depends_on = [
    proxmox_lxc.ansible
  ]

  provisioner "file" {
    source      = var.ansible_private_key
    destination = "/root/.ssh/ansible_key"

    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + var.worker_count + 1}"
      user        = "root"
      private_key = file(var.ssh_private_key)
    }
  }
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /root/.ssh/ansible_key",
      "chown root:root /root/.ssh/ansible_key"
    ]
    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + var.worker_count + 1}"
      user        = "root"
      private_key = file(var.ssh_private_key)
    }
  }
}
