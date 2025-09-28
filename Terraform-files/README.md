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
  ```

This part has been added for post-deployment configuration. I intend to use Ansible playbooks to manage these machines so Python is necessary. `sleep 20` has been added to the `remote-exec` provisioner to allow the network time to come online before attempting to run the other commands.

## Step 4c - Configuring the  Worker VM(s)

It is more likely that there will be multiple Worker VMs created during this step so I wanted these machines to follow the same process of creation as the Master node(s) but assign their IP addresses in sequence after the Master nodes, e.g. master node 192.168.0.170, worker 1 192.168.0.171, worker 2 192.168.0.172, etc. This is intended to assign lower IP addresses to the one or many Master nodes before the Worker nodes.

```
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
}
```

Here, the `ipconfig0` is configured to use local variables to allocate the worker nodes IP addresses after the master node(s) in sequence. This way, master nodes have lower IP addresses but are followed immediately by the worker nodes.

To view the complete deployement script see the accompanying files. the `secrets.tfvars` file will not be included so you will need to create one based off the values found in `variables.tf`.

---

## Step 5 - Initialise Terraform with the required provider for Proxmox.

With the deployment script ready all that is left now is to initialise Terraform in the directory containing the files. CD to the directory and run `terraform init` to begin. This will download the required providers from `main.tf`, downloads modules (if required), and configures the backend (optional).

There will be confirmation on-screen after this is completed, after which you will then be able to run the following commands:

```
"terraform format ." will automatically format config files in the PWD.
"terraform validate" will check the syntax of the config files.
"terraform plan" will show you what Terraform will do
"terraform apply" will show you what it will do with the option to agree and continue
"terraform destroy" will destroy all infrastructre managed by Terraform
```

In my configuration I used `secrets.tfvars` to provide the sensitive information to the `main.tf` file via `variables.tf`. To use these values i needed to specify -var-file="secrets.tfvars" whenever I ran plan or apply. As I knew this would be used for every command in this project I elected to rename the file to `secrets.auto.tfvars` to remove the need to specify it.

---

## Step 6 - Run the deployment to create the VMs

Now to run the script and deploy the machines. `terraform validate` confirmed that the config was syntactically correct, so I ran `terraform plan` to check that Terraform will only be creating resources, not modifying or destroying.

`terraform apply` prepped the deployment, with a simple "yes" in response to the question Terraform began to do the work. The terminal displayed the information about what was happening, including the follow up commands ran to update and upgrade.

---

With the machines provisionaed and ready to go the next part of this project is to deploy Kubernetes to the machines using Ansible.