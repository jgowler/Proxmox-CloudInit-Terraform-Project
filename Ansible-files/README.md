# Create an Ansible playbook to install Kubernetes on the new VMs

---

## Introduction

---

Ansible is an open-source automation tool that configures, manages, and deploys software and infrastructure across multiple servers using simple YAML playbooks. It most commonly runs over SSH for Linux/Unix machines, but also supports other connection methods like WinRM for Windows, local execution, and container or network device APIs, making it ideal for automating tasks, orchestrating deployments, and keeping environments consistent and reproducible.

In this step I will be configuring Ansible playbooks to deploy Kubernetes to the master and worker nodes created in the previous part of this project.

1. Install Ansible.
2. Create an inventory of servers.
3. Test connectivity to the servers using Ansible.
4. Write the playbook.
5. Run the playbook.
6. Verify the results.

---

## Step 1a - Create a VM container to use to run Ansible

---

I will be running Ansible from a seperate VM in Proxmox to run commands on the master and worker node(s) deployed using Terraform. To do this I will create the VM using the same cloud-init template used by the Kubernetes Master / Worker node(s) deployed previously.

```
resource "proxmox_vm_qemu" "ansible" {
  target_node = "homelab"

  name        = "Ansible"
  vmid        = local.starting_vmid + var.master_count + var.worker_count + 1
  clone       = "ubuntu-cloud"
  agent       = 1
  description = "Ansible node - run playbooks from this VM."

  memory     = 2048
  full_clone = true
  scsihw     = "virtio-scsi-single"
  os_type    = "cloud-init"
  boot       = "order=scsi0"

  ciuser     = "ansible"
  cipassword = var.vm_password
  sshkeys    = file(var.ssh_pub_key)
  ipconfig0  = "ip=${local.ansible_ip}/24,gw=${var.gateway_address}"
  nameserver = "8.8.8.8"
  ciupgrade  = true
  skip_ipv6  = true
```

Same as before only with changes required for this VM.

```
  provisioner "file" {
    source      = "./scripts/ansible_setup.sh"
    destination = "/tmp/ansible_setup.sh"
  }
  connection {
    type        = "ssh"
    user        = "root"
    host        = local.ansible_ip
    private_key = file(var.ssh_private_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "chmod +x /tmp/ansible_setup.sh",
      "/tmp/ansible_setup.sh"
    ]
    connection {
      type        = "ssh"
      user        = "root"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
```
Using the same method to copy over the post-deployment script for the other nodes this these provisioners will do the same witht he inclusion of Ansible on top of the other packages.


---

## Step 1b - Create SSH keys so Ansible can reach the master and worker node(s)

---

To ensure the Ansible machine can reach the other nodes created using SSH an SSH keypair will be created during the deployment:

```
resource "tls_private_key" "ansible" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "ansible" {
  depends_on = [
    tls_private_key.ansible
  ]

  content         = tls_private_key.ansible.private_key_pem
  filename        = "${path.module}/ansible-to-k8s"
  file_permission = "0600"
}
```

Here, the key will be created using the `"hashicorp/tls"` and the `"hashicorp/local"` providers. This is added into the providers block then `terraform init --upgrade` is ran.

```
terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}
```
The resource is then created and made into a local file to be provided to the Ansible machine. This is added tot he Ansible machine block:

```
provisioner "file" {
    source      = local_file.ansible.filename
    destination = "/home/ansible/.ssh/ansible-to-k8s"

    connection {
      type        = "ssh"
      user        = "ansible"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 /home/ansible/.ssh/ansible-to-k8s"
    ]
    connection {
      type        = "ssh"
      user        = "ansible"
      host        = local.ansible_ip
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }

  }
```

### NOTE: As the file will be created locally as can be seen in the previous part it must be removed for security reasons.

This public key is then provided to the nodes by modifying the local variable:

```
combined_ssh_keys = join("\n", [file(var.ssh_pub_key), tls_private_keyansible.public_key_openssh])
```

Then `local.combined_ssh_keys` is referenced in the `sshkeys` of the machine deployment; I can SSH from my local computer or from the Ansible machine.

---

## Step 2 - Create an inventory of servers

---

Create an `inventory.ini` file in your Ansible working directory:

```
[workers]
worker1 ansible_host=192.168.0.171 ansible_user=KW1 ansible_ssh_private_key_file=~/.ssh/ansible-to-k8s
worker2 ansible_host=192.168.0.172 ansible_user=KW2 ansible_ssh_private_key_file=~/.ssh/ansible-to-k8s

[masters]
master1 ansible_host=192.168.0.170 ansible_user=KM1 ansible_ssh_private_key_file=~/.ssh/ansible-to-k8s
```

Here, the groups `workers` and `masters` are used to categorise the machines created. `worker1` is a friendly name for th emachine, with `ansible_host` being the machines IP address, `ansible_user` being the user account created on the machine during the deployment, and `ansible_ssh_private_key` being the SSH key used to connect tot he machine over SSH.

---

## Step 3 - Test connectivity to the servers using Ansible

---

We can now test the connection using the following command:

`ansible all -i ansible/inventory.ini -m ping`

This breaks down to:

```
"all" = all hosts in the inventory
"-i ansible/inventory.ini" = tells Ansible where to find the hosts
"-m ping" = uses the ping module
```

If successful we should see a green result returned:

```
[WARNING]: Platform linux on host worker1 is using the discovered Python interpreter at /usr/bin/python3.12, but future installation of another Python
interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-core/2.18/reference_appendices/interpreter_discovery.html for
more information.
worker1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}
[WARNING]: Platform linux on host worker2 is using the discovered Python interpreter at /usr/bin/python3.12, but future installation of another Python
interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-core/2.18/reference_appendices/interpreter_discovery.html for
more information.
worker2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}
[WARNING]: Platform linux on host master1 is using the discovered Python interpreter at /usr/bin/python3.12, but future installation of another Python
interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-core/2.18/reference_appendices/interpreter_discovery.html for
more information.
master1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}
```

This shows that we can connect to the hosts from the Ansible machine.

---

## Step 4 - Write the playbook

---

Now it is time to write the playbook to install Kubernetes on the Master and Worker nodes. First, create the common commands that both workers and masters will use:

```
kubernetes_common.yaml

- name: Setup Kubernetes node (common)
  hosts: all
  become: yes
  gather_facts = yes

  vars:
    kube_version "1.33.4-1.1"
    containerd_config_path "/etc/containerd/config.toml"
    kubernetes_keyring "/etc/apt/keyrings/kubernetes-apt-keyring.gpg"

  tasks:

    # CONTAINERD #
    - name: Update apt package index
    apt:
      update_cache: yes
      # sudo apt update

    - name: Install containerd
      apt:
        name: containerd
        state: present
        # sudo apt-get install containerd -y

    - name: Ensure containerd configuration directory exists
    file:
      path: /etc/containerd
      state: directory
      # sudo mkdir -p /etc/containerd

    - name: Generate containerd default config with custom settings
      command: >
        containerd config default
      register: containerd_default_config
      # containerd config default

    - name: Write customised containerd config
      copy:
        content: "{{ containerd_default_config.stdout
                     | regex_replace('SystemdCgroup = false', 'SystemdCgroup = true')
                     | regex_replace('sandbox_image = \".*\"', 'sandbox_image = \"registry.k8s.io/pause:3.10\"') }}"
        dest: "{{ containerd_config_path }}"
        mode: '0644'
        # containerd config default \
        # | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
        # | sed 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.10"|' \
        # | sudo tee /etc/containerd/config.toml > /dev/null


    - name: Restart containerd
      systemd:
        name: containerd
        state: restart
        enabled: yes
        # sudo systemctl restart containerd

    - name: Disable swap
      command: swapoff -a
      ignore_errors: yes
      # sudo swapoff -a

    - name: Ensure swap is disabled after reboot
      lineinfile:
        path: /etc/fstab
        regexp: '^\s*([^#].*\sswap\s.*)$'
        line: '#\1'
        backrefs: yes

    # KUBEADM, KUBELET, KUBECTL #
    - name: Install prerequisite packages for Kubernetes repo
      apt:
        name:
        - apt-transport-https
        - ca-certificates
        - curl
        - gpg
        state: present

    - name: Create directory for apt keyrings
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Download Kubernetes GPG key
      get_url:
        url: https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key
        dest: "{{ kubernetes_keyring }}"
        mode: ''0644
        force: yes

    - name: Convert GPG key to binary
      command: gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /etc/apt/keyrings/kubernetes-apt-keyring.asc
      args:
        creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    - name: Add Kubernetes APT repository
      copy:
        dest: /etc/apt/sources.list.d/kubernetes.list
        content: |
          deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /
        mode: '0644'

    - name: Update apt after adding Kubernetes repo
      apt:
        update_cache: yes

    - name: Install Kubelet, Kubeadm, and Kubectl
      apt:
        name:
        - "kubelet={{ kube_version }}"
        - "kubeadm={{ kube_version }}"
        - "kubectl={{ kube_version }}"
        state: present

    - name: Hold Kubernetes packages at certain version
      apt:
        name:
        - kubelet
        - kubeadm
        - kubectl
        state: present
        mark: hold

    # Enable IPv4 Forwarding #
    - name: Enable IP packet forwarding temporarily
      systemctl:
        name: net.ipv4.ip_forwarding
        value: 1
        state: present
        reload: yes

    - name: Ensure IP forwarding is enabled after reboot
      lineinfile:
        path: /etc/sysctl.conf
        regexp: '^#?net\.ipv4\.ip_forward=.*'
        line: 'net.ipv4.ip_forward=1'
        state: present
```

This is the common playbook, all nodes will run this to ensure the relevent packages and settings are ready for the master or worker specific playbook that will be run alongside.

---

After the common, master, and worker yaml files are ready (see docs in this repo) the `ansible-playbook-install-kubernetes.yaml` is run to piece it all together. As the hosts are defined by their grouping in inventory.ini and the group is specified in the yaml files to be run then once `ansible-playbook-install-kubernetes.yaml` is run the right packages will be run on the right machines.

---

## Step 5 - Run the playbook

---

Now to run the playbook:

PWD: ~/ansible
`ansible-playbook -i inventory.ini playbooks/ansible-playbook-install-kubernetes.yaml`

The `ansible-playbook-install-kubernetes.yaml` playbook will run the three Kubernetes YAML files created alongside it to run the playbooks in sequence. The `kubernetes_common.yaml` file will do the following:

```
1. Check if Kubernetes is already initialized
Checks for the existence of the kube-apiserver manifest to determine if the control plane is already set up.

2. Initialize the Kubernetes cluster (if not already)
Runs `kubeadm init` with containerd and a pod network CIDR to bootstrap the control plane.

3. Display the output of `kubeadm init`
Prints the full output for visibility and debugging.

4. Extract the `kubeadm join` command from the init output
Greps the join command from the init output and saves it to a temporary file.

5. Generate a fresh join command (if cluster already exists)
Uses `kubeadm token create --print-join-command` to regenerate a valid join command.

6. Read the join command file
Uses Ansible’s `slurp` module to read the file contents in base64 format.

7. Decode and store the join command
Decodes the base64 string and stores the clean join command as a fact (`kubeadm_join_command`).

8. Ensure `.kube` directory exists for the Ansible user
Creates the `.kube` folder in the remote user’s home directory.

9. Copy the admin kubeconfig to the user's `.kube/config`
Enables kubectl access for the Ansible user by copying the admin config.

10. Add `KUBECONFIG` to the user's bash profile
Exports the kubeconfig path for convenience in future shell sessions.

11. Apply the Calico CNI plugin
Installs Calico for pod networking using `kubectl apply`.

12. Display Calico deployment result
Prints the result of the Calico deployment for confirmation.

13. Save the join command to a local file
Copies the join command to the Ansible control machine for use in worker node provisioning.

14. Ensure kubelet systemd drop-in directory exists
Creates the directory for custom kubelet configuration.

15. Configure kubelet to use containerd
Adds a systemd drop-in file to set the container runtime to containerd.

16. Reload systemd and restart kubelet
Applies the new kubelet configuration by restarting the service.
```

The `kubernetes_worker.yaml` will then run and do the following:

```
1. Check that join command file exists on control node
Verifies that the join command file (`kubeadm_join_cmd.txt`) is present on the Ansible control machine.

2. Fail if join command is missing
Stops execution with an error message if the join command file is not found, prompting the user to run the control plane playbook first.

3. Load join command from control node
Reads the contents of the join command file using `slurp`, which returns the data in base64 format.

4. Set join command fact
Decodes the base64 string and stores the clean join command as a fact (`kubeadm_join_command`) for use in the join step.

5. Check if kubelet.conf exists (node already joined)
Checks if the node has already joined the cluster by looking for `/etc/kubernetes/kubelet.conf`.

6. Join worker node to the Kubernetes cluster
Runs the `kubeadm join` command if the node hasn't already joined. Registers the output for review.

7. Display join command output
Prints the result of the join operation for visibility and debugging.

8. Enable and start kubelet service
Ensures the kubelet service is running and enabled to start on boot.

9. Ensure kubelet systemd drop-in directory exists
Creates the directory needed for custom kubelet configuration.

10. Configure kubelet to use containerd
Adds a systemd drop-in file to configure kubelet to use containerd as its container runtime.

11. Reload systemd and restart kubelet
Applies the new configuration by reloading systemd and restarting the kubelet service.
```

After the playbook has finished the cluster is ready to go.

---

## Step 6 - Verify the results

After connecting to the Kubernetes Master node i ran `kubectl get nodes` and the following was returned, showing that the cluster is up and running:

```
NAME                STATUS   ROLES           AGE   VERSION
kubernetesmaster1   Ready    control-plane   52m   v1.34.1
kubernetesworker1   Ready    <none>          46m   v1.34.1
kubernetesworker2   Ready    <none>          46m   v1.34.1
```

And that is it, from creating the cloud-init Ubuntu image and deploying it with Python installed to Proxmox using Terraform to configuring Ansible to run playbooks to create a Kubernetes cluster.

---

## If I were to redo this project

I would add `kubectl taint nodes <MASTER_NODE_NAME> node-role.kubernetes.io/control-plane=:NoSchedule` to prevent pods from being deployed on the Master (unless taint is tolerated by pod), and `kubectl label nodes <WORKER_NODE_NAME> node-role.kubernetes.io/worker=worker` to label the Workers. Another change I would make would be to include a playbook to create a HA cluster, allowing multiple Master nodes to be deployed by including the cert info for the initiated cluster and configuring a load balancer to provide a single endpoint for all nodes to reach the API Server.