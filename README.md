# Rootless Podman

## TL;DR

### 1. Admin user

__Modify__ the [`Makefile`](Makefile) __environment__ to fit yours. 

```bash
make env 
```
- Only `SYS_GROUP_ADMINS` members are allowed to provision (other) AD users.
- Only `SYS_GROUP_DOMAIN_USERS` members are allowed to __self provision__, unless otherwise privileged.

__Install__ (Requires root access)

```bash
make build
make install
```

### 2. Podman user

__Self provision__

```bash
sudo podman-provision-user.sh
```

__Use__

```bash
podman $anything
```

## Why

RedHat has not yet documented a stable, scalable,
fully-functional rootless Podman solution for non-local (AD) 
users seeking a containerized-delvelopment environmnet. 
This local-proxy scheme is a workaround.

## What

Provision a stable rootless Podman environment for a domain (AD) user
by adding a local-proxy user (`podman-$USER`), having nologin shell,
for the otherwise-unprivileged namesake to runas (`sudo -u`). 

This allows for further securing the local proxy by limiting the commands 
allowed of its invoking (AD) sudoer to those declared in a sudoers drop-in. 
That is, sudo is utilized here to limit, not to privilege.

## How

There are many corners to this envelope:

- Lacking privilege, a per-user (rootless) configuration is required:
    - Podman does not configure remote (AD) users.
    - Podman creates per-user namespaces using subids only if
      user is local, regular (non-system), and created after Podman is installed.
    - An active fully-provisioned login shell is expected by Podman to initialize a rootless session.
        - `HOME` is set.
        - `XDG_RUNTIME_DIR` is set.
        - DBus Session Bus starts.
            - Provides user-level IPC.
    - Linux system users, "`adduser --system ...`",
      are not provisioned an active login shell, regardless.
    - Containers running under a rootless process do not survive the user session unless
      Linger is enabled for that user: `sudo loginctl enable-linger <username>`.
        - Also required for Podman's systemd integration schemes.
    - The per-user subid ranges (`subuid`, `subgid`) must be unique per host.
- Workarounds for AD users (__`$USER`__) is to provision a
  logically-mapped __local user__ (__`podman-$USER`__)
  to serve as their Podman service account:
    1. __No login shell__ (`adduser --shell /sbin/nologin ...`)
        - To provide a full functional rootless Podman environment,
          these environment settings must be __explicitly declared__:
            ```bash
            cd /tmp
            sudo -u podman-$USER \
                HOME=/home/podman-$USER \
                XDG_RUNTIME_DIR=/run/user/$(id -u podman-$USER) \
                DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u podman-$USER)/bus \
                /usr/bin/podman "$@"
            ```
            - [`podman.sh`](per-user/podman.sh)
            - Tight security by locking down allowed commands using a group-scoped sudoers drop-in file.
                - [`provision-podman-sudoers.sh`](per-user/podman-provision-sudoers.sh)
    2. __Login shell__ (`adduser --shell /bin/bash ...`)
        - Using SSH shell to trigger an active login session,
        which provides a __fully functional__ rootless Podman environment.
            ```bash
            ssh -i $key podman-$USER@localhost [podman ...]
            ```
            - Secure by locked password, so AuthN/AuthZ is *exclusively* by SSH key/tunnel.

- Privileged ports, e.g., 80 (HTTP) and 443 (HTTPS), are not allowed.

---
