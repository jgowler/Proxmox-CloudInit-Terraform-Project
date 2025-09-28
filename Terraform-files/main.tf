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
  starting_vmid = 400
  base_ip_parts = split(".", var.base_ip)
  base_ip_last  = tonumber(local.base_ip_parts[3])
  ip_prefix     = "${local.base_ip_parts[0]}.${local.base_ip_parts[1]}.${local.base_ip_parts[2]}"
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
  sshkeys    = file(var.ssh_pub_key)
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
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 20",
      "apt update -y",
      "apt upgrade -y",
      "apt install -y qemu-guest-agent python3 python3-pip",
      "systemctl start qemu-guest-agent"
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
  sshkeys    = file(var.ssh_pub_key)
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
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 20",
      "apt update -y",
      "apt upgrade -y",
      "apt install -y qemu-guest-agent python3 python3-pip",
      "systemctl start qemu-guest-agent"
    ]
  }
}
