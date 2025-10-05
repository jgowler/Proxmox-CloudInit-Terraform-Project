#!/usr/bin/env bash
set -eux

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get -o Dpkg::Options::='--force-confold' upgrade -y
apt-get install -y qemu-guest-agent python3 python3-pip software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt-get update -y
apt-get install -y ansible
