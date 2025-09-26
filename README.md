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

---

## Step 2 - Add a Cloud-init drive:

Next, I will need to add a Cloud-init drive to the VM to allow configurations, such as user creation and SSH keys, during deployment.

```
VM > Hardware > Add > Cloudinit Drive:
- Bus/Device: IDE 0
- Storage: "local-lvm"

Add
```
I also removed the CD/DVD drive as this will not be needed, and added a Serial Port:

```
Hardware > Add > Serial Port > 0 > Add
```

Now to add the Cloud Image. For this template I have chosen the current version of "Ubuntu Server 24.04 LTS (Noble Numbat) daily builds" from https://cloud-images.ubuntu.com/.

I ran `wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img` to get the image downloaded to Proxmox.

Then, converted to QCow2:

`qemu-img convert -f raw -O qcow2 noble-server-cloudimg-amd64.img cloud-init-img.qcow2`

To check this I ran `qemu-img info cloud-init-img.qcow2`. This returned the following information:

```
image: cloud-init-img.qcow2
file format: qcow2
virtual size: 32 GiB (34359738368 bytes)
disk size: 591 MiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    compression type: zlib
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
    extended l2: false
Child node '/file':
    filename: cloud-init-img.qcow2
    protocol type: file
    file length: 591 MiB (619381248 bytes)
    disk size: 591 MiB
```

"Virtual size" shows the max size of the disk, whereas disk size shows the current storage being used by the disk (591 MiB).

Next the disk needs to be attached to the VM:

`qm importdisk 9000 cloud-init-img.qcow2 local-lvm`

Under Hardware for the VM there is an "Unused Disk 0". This is the that was just attached that now needs to be configured:

```
Hardware > "Unused Disk 0" > Edit:

Disk
- Discard: Enabled (If using an SSD)
- SSD Emulation: Enabled (If using SSD)

Add
```

The disk will now be listed as a "Hard DIsk (scsi0)" unless any other settings were changed here.

Next, the Boot Order will be changed to disable the Network option and enable the scsi0 disk that was attached.

---

## Step 3 - Convert to template

The final step in this proces is to convert the VM to a template. 

### NOTE: Once a VM is converted to a template it cannot be converted back.

Right-click the VM form the left panel > "Convert to template" > Yes

That's it, a CloudInit Ubuntu template to use in the Terraform deployment.

---

In the next step i will set up a user account and API Token for Terraform to deploy the VM's to Proxmox.