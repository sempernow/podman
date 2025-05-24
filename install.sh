#!/usr/bin/env bash
####################################################################
# Install this project to /usr/local/bin of this host
#
# - Idempotent
####################################################################
set -euo pipefail

[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo bash ${BASH_SOURCE##*/}"

    exit 1
}
src=per-user
dst=/usr/local/bin

bash $src/${APP_PROVISION_SUDOERS}

install $src/${APP_PROVISION_NOLOGIN} $dst/ &&
    install $src/${APP_NAME}.sh $dst/${APP_NAME} &&
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
