#!/usr/bin/env bash
set -eux

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y -o Dpkg::Options::='--force-confold'
apt-get install -y qemu-guest-agent python3 python3-pip
sleep 10
systemctl enable --now qemu-guest-agent