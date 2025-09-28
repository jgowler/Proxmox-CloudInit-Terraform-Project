# Create an Ansible playbook to install Kubernetes on the new VMs

---

## Introduction

Ansible is an open-source automation tool that configures, manages, and deploys software and infrastructure across multiple servers using simple YAML playbooks. It most commonly runs over SSH for Linux/Unix machines, but also supports other connection methods like WinRM for Windows, local execution, and container or network device APIs, making it ideal for automating tasks, orchestrating deployments, and keeping environments consistent and reproducible.

In this step I will be configuring Ansible playbooks to deploy Kubernetes to the master and worker nodes created in the previous part of this project.

1. Install Ansible.
2. Create an inventory of servers.
3. Test connectivity to the servers using Ansible.
4. Write the playbook.
5. Run the playbook.
6. Verify the results.

---

## Step 1a - Create an LXC container to use to run Ansible

I will be running Ansible from an LXC container in Proxmox to run commands on the master and worker node(s) deployed using Terraform. To do this I will create the LXC container using a template already stored in Proxmox.

To list the templates available  ran `ls /var/lib/vz/template/cache/` and used `ubuntu-24.04-standard_24.04-2_amd64.tar.zst`.

Using this template I scripted the LXC to be created:

```
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
```

This created an unpriviledged container using the template in `template/cache` with 8Gb of storage. The IP address follows the same process as the worker nodes in following in sequence. The same SSH public key used to access the master and worker nodes is used here also.

Once it is up and running the `remote-exec` provisioner will run to install the same packages as the VMs with the addition of the commands required to install Ansible and also install, start, and enable OpenSSH.

This is then followed by the transfer of the SSH private key to the LXC of which the public key has been added. The VMs have been updated to upload the public SSH key for the Ansible LXC also to allow the connection:

```
locals {
    ...
    combined_ssh_keys = join("\n", [file(var.ssh_pub_key), file(var.ansible_public_key)])
}

resource "proxmox_vm_qemu" "kubernetes_master" {
    ...
    sshkeys    = local.combined_ssh_keys
    ...
}
```

Going back to the LXC a provisioner block is added to transfer the SSH provate key it will use to connect tot he VMs:

```
resource "null_resource" "copy_ansible_private_key" {

  depends_on = [
    proxmox_lxc.ansible
  ]

  provisioner "file" {
    source      = file(var.ansible_private_key)
    destination = "/root/.ssh/ansible_key"

    connection {
      type        = "ssh"
      host        = "${local.ip_prefix}.${local.base_ip_last + var.master_count + var.worker_count + 1}"
      user        = "root"
      private_key = var.ssh_private_key
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
```

This will connect using the SSH key pair, copy the Private key over to the LXC and `remote-exec` will change the permissions on the .ssh folder 
to grant the owner read and write permissions, ownership of the folder will be granted to the root user.

