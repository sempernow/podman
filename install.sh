#!/usr/bin/env bash
####################################################################
# Install this project to /usr/local/bin of this host
#
# - Idempotent
####################################################################
[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo ${BASH_SOURCE##*/}"

    exit 1
}
logger "Script run by '$SUDO_USER' as root : '$BASH_SOURCE'"

src=per-user
dst=/usr/local/bin
install $src/podman-provision-nologin.sh $dst/ &&
    install $src/podman.sh $dst/podman &&
        echo "✅  Installation complete." ||
            echo "❌  Something failed to install."

exit $?
#######

install $src/podman-provision-sudoers.sh $dst/ &&
    install $src/podman-provision-nologin.sh $dst/ &&
        install $src/podman-unprovision-user.sh $dst/ &&
            install $src/podman.sh $dst/podman &&
                echo "✅  Installation complete." ||
                    echo "❌  Something failed to install."
