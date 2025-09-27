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

Download the cloud image from `https://cloud-images.ubuntu.com/`

I selected `https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`

Download:
`wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`

Import the disk:
`qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm`

```

Create virtual machine:

qm create 9000 \
--memory 1024 \
--core 1 \
--name ubuntu-cloud \
--net0 virtio,bridge=vmbr0 \
--bootdisk scsi0 \
--scsihw virtio-scsi-pci \
--serial0 socket --vga serial0

```

Next, add the cloud image drive to the vm
`qm set 9000 --scsi0 local-lvm:vm-9000-disk-0`

Resize the disk
`qm resize 9000 scsi0 32G`

---

## Step 2 - Add a Cloud-init drive:

Next, I will need to add a Cloud-init drive to the VM to allow configurations, such as user creation and SSH keys, during deployment.

```

qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0

```

NOTE: Adding `qm set 9000 --boot c --bootdisk scsi0` ensures the boot drive will be the cloud image.
 
---

## Step 3 - Convert to template

The final step in this proces is to convert the VM to a template. 

### NOTE: Once a VM is converted to a template it cannot be converted back.

Right-click the VM form the left panel > "Convert to template" > Yes

That's it, a CloudInit Ubuntu template to use in the Terraform deployment.

---

In the next step i will [set up a user account and API Token for Terraform to deploy the VM's to Proxmox](https://github.com/jgowler/Proxmox-CloudInit-Terraform-Project/tree/main/Proxmox-files).