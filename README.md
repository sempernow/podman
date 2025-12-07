# Rootless Podman

## UPDATE

WS2019 to RHEL integration 

Use IdM, RedHat's branded FreeIPA, to manage Podman subid assignments for domain users.

- https://www.julioloayzam.com/blog/podman-freeipa-and-subuids/
- https://freeipa.readthedocs.io/en/ipa-4-11/designs/subordinate-ids.html
- https://access.redhat.com/solutions/6961540

---

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

[RedHat has not yet documented a stable, scalable,
fully-functional rootless Podman solution for non-local (AD) 
users seeking a containerized-delvelopment environmnet](https://access.redhat.com/solutions/6216591). 
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

## Q:

It seems __Tenable scanner__ declares the namespaced Podman resources some kind of security violation for having owner and/or group that do not exist on host. 
Is this a known issue, or is something misconfigured?

## A:

Yes, this **is a known situation** when working with **Podman (especially in rootless mode or when using UID/GID namespaces)** — but whether it *should* be declared a security violation depends on **scanner policy tuning** and **context**.

### 🔍 Why This Happens

When you use **namespaced or rootless containers**, Podman maps container UIDs/GIDs to host UIDs/GIDs using **`/etc/subuid` and `/etc/subgid`** ranges. This mapping allows unprivileged users to run containers as if they were root inside the container.

However:

* Files created inside the container may appear **on the host filesystem** with UID/GID values that **do not map to real users/groups** on the host — because they're from the **mapped range**, not standard system UIDs.
* For example, you might see files owned by UID **100000+** or GID **100000+** — these are **valid in the container's view**, but not recognizable to `ls -l` or to scanners on the host.

Tenable and similar scanners (like Nessus, OpenSCAP, etc.) often flag such ownership as a **misconfiguration or security concern** because they see these as:

* Orphaned files (no corresponding `/etc/passwd` or `/etc/group` entry),
* Files with unexpected ownership that may allow privilege escalation if not properly sandboxed.

---

### ✅ Is It Misconfigured?

**Not necessarily** — if:

* You're using **rootless Podman** with proper `subuid/subgid` mappings,
* And these files are **within storage paths managed by Podman**, such as `~/.local/share/containers` or `/var/lib/containers`.

Then it's **expected** behavior.

However, it **might be a concern** if:

* You're mounting **container volumes to the host filesystem** outside controlled areas (e.g. shared NFS paths or home directories),
* Or the files appear in **host-visible paths** and break ACL/SELinux assumptions,
* Or you haven't configured `subuid/subgid` properly and fallback UIDs are being used.

---

### 🔐 What to Do

Depending on your risk profile and audit requirements:

#### 1. **Tune the Scanner**

* Tell Tenable to **ignore UID/GID > 65535** for container-managed paths.
* Whitelist known container storage paths from alerts.

#### 2. **Check Podman UID Mapping**

* Ensure each container-running user has proper entries in `/etc/subuid` and `/etc/subgid`:

  ```bash
  grep ^$USER: /etc/subuid
  grep ^$USER: /etc/subgid
  ```

#### 3. **Control Mounts**

* Avoid mounting sensitive host paths into containers without remapping.
* Use `--userns=keep-id` or `--uidmap` only when needed.

#### 4. **Use `fuse-overlayfs` or Shadow Mapping**

* If container data must appear on the host, use `fuse-overlayfs` or shadow mounts to present ownership cleanly.

#### 5. **Use Namespace-Aware Scanners**

* Some modern tools (like OpenSCAP in container-aware mode) understand user namespaces and will not falsely flag these.

---

### Summary

> **Not a misconfiguration**, but a **false positive** unless containers are breaking isolation or leaking UID-mapped files into sensitive host paths. Adjust scanner policies and review your volume mounts and UID mappings.

Let me know if you'd like to confirm your current `subuid/subgid` mappings or sanitize paths from scanner alerts.
