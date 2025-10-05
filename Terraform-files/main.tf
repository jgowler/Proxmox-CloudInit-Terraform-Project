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
      "while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 1; done",
      "apt-get install -f -y || true",
      "apt-get update -y",
      "apt-get -o Dpkg::Options::='--force-confold' upgrade -y || apt-get install -f -y",
      "apt-get install -y -o Dpkg::Options::='--force-confold' qemu-guest-agent python3 python3-pip || apt-get install -f -y",
      "systemctl enable --now qemu-guest-agent || true"
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

  ##

  connection {
    type        = "ssh"
    host        = local.ansible_ip
    user        = "root"
    private_key = file(var.ssh_private_key)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get -o Dpkg::Options::='--force-confold' upgrade -y || apt-get -f install -y",
      "apt-get install -y qemu-guest-agent openssh-server python3 python3-pip software-properties-common || apt-get install -f -y",
      "dpkg-reconfigure openssh-server || true",
      "mkdir -p /run/sshd",
      "/usr/sbin/sshd || true",
      "systemctl start qemu-guest-agent || true",
      "add-apt-repository --yes --update ppa:ansible/ansible || true",
      "apt-get update -y",
      "apt-get install -y ansible || apt-get install -f -y",
      "sed -i '/^#\\?PasswordAuthentication /d;/^#\\?PermitRootLogin /d;/^#\\?PubkeyAuthentication /d' /etc/ssh/sshd_config",
      "printf 'PasswordAuthentication no\\nPermitRootLogin prohibit-password\\nPubkeyAuthentication yes\\n' > /etc/ssh/sshd_config",
      "systemctl restart ssh || /usr/sbin/sshd || true"
    ]
  }

  ##

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for SSH to become available...'",
      "until nc -zv localhost 22; do sleep; done"
    ]
    connection {
      type        = "ssh"
      host        = local.ansible_ip
      user        = "root"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
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
      host        = local.ansible_ip
      user        = "root"
      private_key = file(var.ssh_private_key)
    }
  }
}

resource "null_resource" "fix_ssh" {
  depends_on = [
    proxmox_lxc.ansible
  ]

  provisioner "file" {
    source      = "ansible_ssh_fix.sh"
    destination = "/tmp/ansible_ssh_fix.sh"

    connection {
      type        = "ssh"
      host        = local.ansible_ip
      user        = "root"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/ansible_ssh_fix.sh",
      "bash /tmp/ansible_ssh_fix.sh \"$(echo ${file(var.ssh_pub_key)} | tr -d '\\n')\""
    ]
    connection {
      type        = "ssh"
      host        = local.ansible_ip
      user        = "root"
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
}
