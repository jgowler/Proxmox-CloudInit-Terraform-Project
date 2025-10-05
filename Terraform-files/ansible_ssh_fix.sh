#!/bin/bash
set -eux
SSH_KEY="$1"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "$SSH_KEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chown root:root /root/.ssh/authorized_keys
