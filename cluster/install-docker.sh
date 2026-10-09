#!/usr/bin/env bash
# Usage, sur chaque noeud : ssh manager 'bash -s' < cluster/install-docker.sh
set -euo pipefail
VERSION=5:29.8.2-1~debian.13~trixie

sudo apt-get update -q
sudo apt-get install -yq ca-certificates curl make
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<SRC
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SRC
sudo apt-get update -q
sudo apt-get install -yq "docker-ce=$VERSION" "docker-ce-cli=$VERSION" containerd.io

# le reseau Proxmox est a 1350
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{ "mtu": 1350, "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
JSON
sudo systemctl enable --now docker
sudo systemctl restart docker
sudo usermod -aG docker "$USER"
docker --version 2>/dev/null || sudo docker --version
