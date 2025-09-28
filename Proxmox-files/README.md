# Proxmox - Set up user and API Token for Terraform

---

## Introduction

In this step of the project I will need to create a user account and API Token for Terraform to use to deploy the VM's to my homelab.

1. Create a user account in Proxmox for Terraform to use.
2. Create an API Token with the specific permissions to connect to Proxmox.
3. Create a custom role in Proxmox for the API Token.
4. Assign the role to the Terraform user.

---

## Step 1 - Create a user account in Proxmox for Terraform to use

```
Datacenter > Users > Add
- User name: "terraform"
- Realm: "Proxmox VE authentication server"
- Password / Confirm password: Choose a password.

Add
```

That's it, the permissions will be granted to the API Token that will be assigned to this user account.

---

## Step 2 - Create the API Token

For this project I will be using the Telmate Proxmox provider found here: https://registry.terraform.io/providers/Telmate/proxmox/latest

The documentation goes into detail on how to grant the permissions to a user account, but I will instead be granting these to the API Token itself instead and assigning it to the user.

```
Datacenter > API Tokens > Add
- User: "terraform@pve"
- Token ID: "terraform"
- Priviledge Seperation: Disabled

Add
```

Here you will be presented with the Token ID and the Secret. Take note of these as once this box is closed you will not have another chance to take this info!

---

## Step 3 - Create a custom role in Proxmox for the API Token

Next, a Role will need to be created to apply to the API Token

```
Datacenter > Roles > Create
- Name: "TerraformDeployment"
- Priviledges:

Here are the permissions with a brief explanation:

Datastore
Datastore.AllocateSpace – Allocate storage space
Datastore.AllocateTemplate – Allocate VM templates
Datastore.Audit – Audit/read datastore information

Pool
Pool.Allocate – Create and manage resource pools

System
Sys.Audit – Audit/read system configuration
Sys.Console – Console access
Sys.Modify – Modify system configuration

Virtual Machine (VM)
VM.Allocate – Create/remove VMs
VM.Audit – Audit/read VM configuration
VM.Clone – Clone VMs
VM.Config.CDROM – Configure CD/DVD drives
VM.Config.Cloudinit – Configure cloud-init
VM.Config.CPU – Configure CPU settings
VM.Config.Disk – Configure virtual disks
VM.Config.HWType – Configure hardware type (BIOS, machine type, etc.)
VM.Config.Memory – Configure memory
VM.Config.Network – Configure network devices
VM.Config.Options – Configure general VM options
VM.Migrate – Migrate VMs (live/offline)
VM.Monitor – Access VM monitor (QEMU monitor commands)
VM.PowerMgmt – Power management (start/stop/reboot/suspend)

SDN (Software Defined Networking)
SDN.Use – Use SDN objects

Create
```

---

## Step 4 - Assign the role to the Terraform user

Now to add the permissions to the Terraform user

```
Datacenter > Permissions > Add > User Permission
- Path: "/"
- User: "terraform@pve"
- Role: "TerraformDeployment"
- Propogate: Enabled

Add
```

---

That's it, the Terraform user, bespoke role, and API Token have all been created ready for [Terraform to use for deployment to Proxmox.](https://github.com/jgowler/Proxmox-CloudInit-Terraform-Project/tree/main/Terraform-files)