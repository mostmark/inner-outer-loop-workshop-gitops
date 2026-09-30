#!/bin/sh
#
# Sourced by entrypoint.sh before the container command starts.
#
# The Maven mirror is configured in the global settings ($MAVEN_HOME/conf/settings.xml), which
# reads the MAVEN_MIRROR_URL environment variable, so nothing has to be written to ~/.m2 here.
# Add workspace start-up steps to this file if the image ever needs them.

# Make sure the Maven repository folder exists (it is usually a volume mounted by the devfile).
mkdir -p "${HOME}/.m2" 2> /dev/null || true

return 0
