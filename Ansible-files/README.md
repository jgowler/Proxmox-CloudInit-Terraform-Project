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

## Step 1 - Install Ansible