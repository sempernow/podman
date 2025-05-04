#!/usr/bin/env bash

# Stop all containers
podman stop -a

# Remove all containers
podman rm -a

# Remove all images
podman rmi -a

# Remove all volumes
podman volume rm -a

# Remove all pods
podman pod rm -a

podman system prune --all --volumes --force
podman system prune --all --force
