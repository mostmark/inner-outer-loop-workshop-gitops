#!/bin/sh
#
# Copyright (c) 2018-2019 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#

set -e

uid=$(id -u)
gid=$(id -g)

# OpenShift runs the container with an arbitrary UID (GID 0). Add a passwd entry for it so that
# tools which look up the current user (git, ssh, maven, whoami) work. /etc/passwd is group-writable.
if ! whoami > /dev/null 2>&1; then
  echo "${USER_NAME:-user}:x:${uid}:0:${USER_NAME:-user} user:${HOME}:/bin/bash" >> /etc/passwd
fi

# Grant access to the projects volume for a non-root user with sudo rights (not the case on OpenShift)
if [ "${uid}" -ne 0 ] && command -v sudo > /dev/null 2>&1 && sudo -n true > /dev/null 2>&1; then
  sudo chown "${uid}:${gid}" /projects
fi

[ -f "${HOME}/before-start.sh" ] && . "${HOME}/before-start.sh"

exec "$@"
