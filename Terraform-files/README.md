# Write the Terraform deployment script to create the VM's, deploy Kubernetes on the nodes, and install Python

---

## Introduction

In this step of the project I will create the edployment files to instruct Terraform to connect to my Proxmox homelab using the user account created previously and the API token.

1. Install Terraform locally.
2. Create the secrets file to store sensitive data.
3. Create the variables file to store data.
4. Create the main file to deploy the VMs to Proxmox using Terraform.
5. Initialise Terraform with the required provider for Proxmox.
6. Run the deployment to create the VMs.
---

## Step 1 - Install Terraform locally

To install Terraform I used the official documentation for Windows installation: https://developer.hashicorp.com/terraform/install
To verify the installation i ran `terraform -help` to confirm. This brought up the help documentation for Terraform, confirming it is installed.

---

## Step 2 - Create the secrets file to store sensitive data

To safely store sensitive data for this project i will save it all in a file called `secrets.tfvars`. I have added `*.tfvars` to my .gitignore file to ensure it is not uploaded to GitHub.

The following are the variables for each secret:

```

secrets.tfvars

pm_api_url: https://<proxmox-host>:8006/api2/json
pm_user: "terraform@pve"
pm_api_token_id: "terraform@pve!terraform"
pm_api_token_secret: This is the secret created with the API Token.
```

---

## Step 3 - Create the variables file to store data

All of the variables which I will apply to the `main.tf` will be stored in `variables.tf`, with the values stored in `secrets.tfvars` applying over the default values stored here

```

variables.tf

variable "pm_api_url" {
  description = "URL of Proxmox"
  type        = string
}
variable "pm_user" {
  description = "Terraform user acocunt for Proxmox"
  type        = string
}
variable "pm_api_token_id" {
  description = "API Token used by Terraform user"
  type        = string
  sensitive   = true
}
variable "pm_api_token_secret" {
  description = "API Token secret"
  type        = string
  sensitive   = true
}
variable "ssh_pub_key" {
  description = "SSH pub key location"
  type        = string
  sensitive   = true
}

```

`sensitive = true` has been included here to ensure these values are not shown in the output.

---

## Step 4a - Create the main file to deploy the VMs to Proxmox using Terraform

Now to write the deplyment scrip `main.tf` which will provide instructions to Terraform on where and how it will deploy the VMs

The provider I will use for this is Telmate Proxmox: https://registry.terraform.io/providers/Telmate/proxmox/latest

The "use provider" tab shows that the following provider block will be required:

```

main.tf

terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
    pm_api_url = var.pm_api_url
    pm_user = var.pm_user
    pm_api_token_id = var.pm_api_token_id
    pm_api_token_secret = var.pm_api_token_secret
    pm_tls_insecure = true
}
```

The second half of this contains the connection information Terraform will use to access Proxmox. `pm_tls_insecure = true` has been included as I have not set up TLS for my homelab Proxmox, but this may not be the case for you.


## Step 4b - Configuring the  Master VM(s)

There are a few things that need to be set up when creating the Master VM from such a bare template:

```
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
```

In this part I want to ensure I could create mroe than one kubernetes master node should it be required. The name of the VM will be numbered to indicate which iteration of this machine is created and the `ipconfig0` section provisions the IP address of the node depending on which iteraction it is to keep things organised. No password for the user account has been provided here as to only allow access to the VM using SSH keys.

```
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
  ```

  In this section the serrial port, cpu, network, and disks are configured.

  ```
  connection {
    type        = "ssh"
    host        = "192.168.0.17${count.index}"
    user        = "root"
    private_key = file(var.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = [
      "apt update -y",
      "apt upgrade -y",
      "apt install -y qemu-guest-agent",
      "systemctl enable qemu-guest-agent",
      "systemctl start qemu-guest-agent",
      "apt update -y",
      "apt install -y python3 python3-pip"
    ]
  }
  ```

  This part has been added for post-deployment configuration. I intend to use Ansible playbooks to manage these machines so Python is necessary. 

  ## Step 4b - Configuring the  Worker VM(s)

  It is more likely that there will be multiple Worker VMs created during this step so I wanted these machines to follow the same process of creation as the Master node(s) but assign their IP addresses in sequence after the Master nodes, e.g. master node 192.168.0.170, worker 1 192.168.0.171, worker 2 192.168.0.172, etc. This is intended to assign lower IP addresses to the one or many Master nodes before the Worker nodes.


