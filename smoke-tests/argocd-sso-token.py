#!/usr/bin/env python3
"""Logs in to the participant Argo CD the way a browser does ("LOG IN VIA OPENSHIFT"): Argo CD ->
Dex -> OpenShift OAuth -> identity provider login form -> OAuth consent -> back to Argo CD, and
prints the resulting Argo CD session token (the argocd.token cookie). Used by isolation-check.sh
to verify the SSO path and its RBAC mapping.

Usage: WORKSHOP_USER_PASSWORD=<the user's password> argocd-sso-token.py <username> <apps-domain> [argocd-route-host-prefix]
       (default prefix: argocd-server-argocd, the participant instance; isolation-check.sh sets
       WORKSHOP_USER_PASSWORD to the user's own password, also when users have different ones)
Supports the Keycloak login form (kc-form-login) and the OpenShift htpasswd/basic login page.
"""
import html
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse

user, domain = sys.argv[1], sys.argv[2]
prefix = sys.argv[3] if len(sys.argv) > 3 else "argocd-server-argocd"
password = os.environ["WORKSHOP_USER_PASSWORD"]
work = tempfile.mkdtemp()
jar, body_file = os.path.join(work, "jar"), os.path.join(work, "body")


def curl(url, data=None):
    cmd = ["curl", "-sk", "-b", jar, "-c", jar, "-o", body_file, "-w", "%{http_code} %{redirect_url}"]
    if data is not None:
        cmd += ["--data", urllib.parse.urlencode(data)]
    code, _, location = subprocess.check_output(cmd + [url]).decode().partition(" ")
    with open(body_file, errors="ignore") as f:
        return int(code), location, f.read()


url = f"https://{prefix}.{domain}/auth/login"
for _ in range(30):
    code, location, body = curl(url)
    host = urllib.parse.urlparse(url).netloc
    if code in (301, 302, 303, 307) and location:
        url = location
    elif code == 200 and "kc-form-login" in body:  # Keycloak (Red Hat build of Keycloak)
        action = html.unescape(re.search(r'id="kc-form-login"[^>]*action="([^"]+)"', body).group(1))
        code, url, _ = curl(action, {"username": user, "password": password, "credentialId": ""})
    elif code == 200 and host.startswith("oauth-openshift") and "/approve" in url:  # OAuth consent
        form = re.search(r'<form[^>]*action="([^"]*)"', body)
        inputs = re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"', body)
        data = [(k, html.unescape(v)) for k, v in inputs] + [("approve", "Allow selected permissions")]
        code, url, _ = curl(urllib.parse.urljoin(url, html.unescape(form.group(1)) if form else ""), data)
    elif code == 200 and host.startswith("oauth-openshift") and 'name="username"' in body:  # htpasswd login
        form = re.search(r'<form[^>]*action="([^"]*)"', body)
        inputs = dict(re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"', body))
        inputs.update({"username": user, "password": password})
        code, url, _ = curl(urllib.parse.urljoin(url, html.unescape(form.group(1))), inputs)
    elif code == 200 and host.startswith("oauth-openshift") and "idp=" in body:  # identity provider choice
        url = urllib.parse.urljoin(url, html.unescape(re.search(r'href="([^"]*idp=[^"]*)"', body).group(1)))
    else:
        break

with open(jar) as f:
    tokens = [line.split()[-1] for line in f if "\targocd.token\t" in line]
if not tokens:
    sys.exit("no Argo CD session token (login failed)")
print(tokens[-1])
