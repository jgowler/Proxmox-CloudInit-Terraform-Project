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
}

# Create VMs

resource "proxmox_vm_qemu" "kubernetes_master" {
  count       = 1
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
  ipconfig0  = "ip=192.168.0.17${count.index}/24,gw=192.168.0.1"
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
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
}
