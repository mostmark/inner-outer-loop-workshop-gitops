#!/bin/bash
# Workshop user passwords, shared by bootstrap.sh, print-user-urls.sh and the smoke tests.
# Source it; do not run it.
#
# Two modes:
#   shared (default)  every user has the same password: WORKSHOP_USER_PASSWORD
#   per user          every user has their own password, listed in a credentials file:
#                     --credentials-file FILE or WORKSHOP_CREDENTIALS_FILE
#
# Credentials file format (never commit it): one "username,password" per line. Empty lines and
# lines starting with # are ignored, and so is a header line "username,password". The password is
# everything after the first comma (it may contain commas); a trailing CR (Windows line ending) is
# removed.
#
# In the cluster, bootstrap.sh stores the passwords in Secret workshop-user-password (namespace
# gitea): key "userPassword" in shared mode, one key "password.<user>" per user otherwise.

CREDENTIALS_SECRET_NAMESPACE=gitea
CREDENTIALS_SECRET_NAME=workshop-user-password

# creds_file_users <file>: prints the users listed in a credentials file, one per line.
creds_file_users() {
  awk -F, '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    { user = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", user) }
    NR == 1 && tolower(user) == "username" { next }
    user != "" { print user }' "$1"
}

# creds_file_password <file> <user>: prints the user's password from a credentials file.
# Returns 1 if the user is not in the file.
creds_file_password() {
  awk -F, -v wanted="$2" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    { user = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", user) }
    user == wanted && index($0, ",") > 0 { print substr($0, index($0, ",") + 1); found = 1; exit }
    END { exit found ? 0 : 1 }' "$1"
}

# creds_cluster_password <user>: prints the user's password from the cluster Secret (needs read
# access to it, e.g. cluster-admin). Returns 1 if there is none.
creds_cluster_password() {
  local key value
  for key in "password\\.$1" "userPassword"; do
    value=$(oc get secret "$CREDENTIALS_SECRET_NAME" -n "$CREDENTIALS_SECRET_NAMESPACE" \
      -o jsonpath="{.data.${key}}" 2>/dev/null)
    if [[ -n "$value" ]]; then
      printf '%s' "$value" | base64 -d
      return 0
    fi
  done
  return 1
}

# user_password <user>: the password of a workshop user, from (in this order) the credentials
# file (WORKSHOP_CREDENTIALS_FILE), the cluster Secret (what the workshop was set up with; needs
# read access to it), or WORKSHOP_USER_PASSWORD. The Secret comes before the environment variable
# so that a shared password still exported in the shell cannot override per-user passwords.
user_password() {
  if [[ -n "${WORKSHOP_CREDENTIALS_FILE:-}" ]]; then
    creds_file_password "$WORKSHOP_CREDENTIALS_FILE" "$1"
  elif creds_cluster_password "$1"; then
    :
  elif [[ -n "${WORKSHOP_USER_PASSWORD:-}" ]]; then
    printf '%s' "$WORKSHOP_USER_PASSWORD"
  else
    return 1
  fi
}

# creds_check_source: fails with a message if a credentials file is configured but unreadable.
creds_check_source() {
  if [[ -n "${WORKSHOP_CREDENTIALS_FILE:-}" && ! -r "$WORKSHOP_CREDENTIALS_FILE" ]]; then
    echo "Error: credentials file '$WORKSHOP_CREDENTIALS_FILE' is not readable." >&2
    return 1
  fi
}
