# Deploy Cloud-init templated VM's to Proxmox using Terraform

---

## Introduction

This project will be to create Cloud-init templates of Ubuntu server to be used to deploy a Kubernetes Master node and two Worker nodes in my Proxmox homelab environment. During the deployment Terraform will coordinate the creation of the VM's with the deployment of Kubernetes on the nodes in order to add the workers to the cluster after their creation in one single deployment. I will also be installing Python onto the machines to manage them using Ansible playbooks.

---

## How will I do this?

I will be structuring the project in this order:

1. Create a Cloud-init image of Ubuntu server using a Cloud image.
2. Create a user account in Proxmox for Terraform to use.
3. Create an API Token with the specific permissions to connect to Proxmox.
4. Write the Terraform deployment script to create the VM's, deploy Kubernetes on the nodes, and install Python.
5. Create an Ansible playbook to run updates on the nodes over SSH.

---

## Step 1 - Create a Cloud-init image of Ubuntu server using a Cloud image:

First step is to create the VM to be used as a Template for the VM's.

```
Proxmox > Create VM

General:
- Node: "homelab"
- Name: "Ubuntu-Cloud"

OS:
- Choose "Do not use any media"

System:
- Machine: "q35"
- BIOS: "OVMF (UEFI)"
- EFI Storage: "local-lvm" (this may differ depending on your setup)
- Qemu Agent: Enabled

Disks:
- I chose to remove the default scsi disk as the disk will be configured later.

CPU:
- Sockets: 1
- Core: 1
(These will be configured on the VM's created using the template)

Memory:
- Memory (MiB): 1024
- Ballooning: Disabled
(Again, this will be configured during deployment)

Network:
- Bridge: "vmbr0" (This may be different depending on your setup)

Confirm:
- Start after created: Disabled.

Finish
```
