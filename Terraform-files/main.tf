terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
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
  combined_ssh_keys = join("\n", [file(var.ssh_pub_key), tls_private_key.ansible.public_key_openssh])
}

# Create VMs

resource "proxmox_vm_qemu" "kubernetes_master" {
  depends_on = [
    tls_private_key.ansible
  ]

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

  ciuser     = "KM${count.index + 1}"
  cipassword = var.vm_password
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

  provisioner "file" {
    source      = "./scripts/vm_setup.sh"
    destination = "/tmp/vm_setup.sh"

    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + count.index}"
      user        = "KM${count.index + 1}"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "sudo chmod +x /tmp/vm_setup.sh",
      "sudo /tmp/vm_setup.sh"
    ]
    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + count.index}"
      user        = "KM${count.index + 1}"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
}

# Worker node config

resource "proxmox_vm_qemu" "kubernetes_worker" {
  depends_on = [
    tls_private_key.ansible
  ]

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

  ciuser     = "KW${count.index + 1}"
  cipassword = var.vm_password
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
  ##
  provisioner "file" {
    source      = "./scripts/vm_setup.sh"
    destination = "/tmp/vm_setup.sh"

    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + count.index}"
      user        = "KW${count.index + 1}"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "sudo chmod +x /tmp/vm_setup.sh",
      "sudo /tmp/vm_setup.sh"
    ]
    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + count.index}"
      user        = "KW${count.index + 1}"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
}

resource "proxmox_vm_qemu" "ansible" {
  depends_on = [
    tls_private_key.ansible
  ]

  target_node = "homelab"

  name        = "Ansible"
  vmid        = local.starting_vmid + var.master_count + var.worker_count + 1
  clone       = "ubuntu-cloud"
  agent       = 1
  description = "Ansible node - run playbooks from this VM."

  memory     = 2048
  full_clone = true
  scsihw     = "virtio-scsi-single"
  os_type    = "cloud-init"
  boot       = "order=scsi0"

  ciuser     = "ansible"
  cipassword = var.vm_password
  sshkeys    = file(var.ssh_pub_key)
  ipconfig0  = "ip=${local.ansible_ip}/24,gw=${var.gateway_address}"
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

  provisioner "file" {
    source      = "./scripts/ansible_setup.sh"
    destination = "/tmp/ansible_setup.sh"
  }
  connection {
    type        = "ssh"
    user        = "ansible"
    host        = local.ansible_ip
    private_key = file(var.ssh_private_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "sudo chmod +x /tmp/ansible_setup.sh",
      "sudo /tmp/ansible_setup.sh"
    ]
    connection {
      type        = "ssh"
      user        = "ansible"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
  provisioner "file" {
    source      = local_file.ansible.filename
    destination = "/home/ansible/.ssh/ansible-to-k8s"

    connection {
      type        = "ssh"
      user        = "ansible"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 /home/ansible/.ssh/ansible-to-k8s"
    ]
    connection {
      type        = "ssh"
      user        = "ansible"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }

  }
}

resource "tls_private_key" "ansible" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "ansible" {
  depends_on = [
    tls_private_key.ansible
  ]

  content         = tls_private_key.ansible.private_key_pem
  filename        = "${path.module}/ansible-to-k8s"
  file_permission = "0600"
}
