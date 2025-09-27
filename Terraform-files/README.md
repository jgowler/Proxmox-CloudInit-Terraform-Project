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

## Step 4 - Create the main file to deploy the VMs to Proxmox using Terraform

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


