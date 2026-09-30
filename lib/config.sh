#!/usr/bin/env bash

config_load_transport() {
    local config_file="$1"
    local domain="$2"
    local transport="$3"

    command -v python3 >/dev/null 2>&1 || {
        echo "ERROR: python3 is required to read deploy.json" >&2
        return 1
    }

    [[ -f "${config_file}" ]] || {
        echo "ERROR: missing deployment config: ${config_file}" >&2
        return 1
    }

    local assignments
    if ! assignments="$(
        python3 - "${config_file}" "${domain}" "${transport}" <<'PY'
import json
import shlex
import sys

path, domain, transport = sys.argv[1:4]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

if data.get("version") != 1:
    raise SystemExit("deploy.json: unsupported or missing version")

domains = data.get("domains")
if not isinstance(domains, dict) or domain not in domains:
    raise SystemExit(f"deploy.json: domain not configured: {domain}")

domain_cfg = domains[domain]
if not isinstance(domain_cfg, dict) or transport not in domain_cfg:
    raise SystemExit(
        f"deploy.json: transport '{transport}' not configured for domain '{domain}'"
    )

cfg = domain_cfg[transport]
if not isinstance(cfg, dict):
    raise SystemExit("deploy.json: transport config must be an object")

defaults = data.get("defaults", {})
overwrite_default = defaults.get("overwrite_default", True)
if not isinstance(overwrite_default, bool):
    raise SystemExit("deploy.json: defaults.overwrite_default must be boolean")

def required(name):
    value = cfg.get(name)
    if value is None or value == "":
        raise SystemExit(
            f"deploy.json: missing domains.{domain}.{transport}.{name}"
        )
    return value

host = required("host")
port = required("port")
user = required("user")
remote_root = required("remote_root")

password = cfg.get("password", "")
auth = cfg.get("auth", "")
identity_file = cfg.get("identity_file", "")

if transport == "ftp":
    required("password")
elif transport == "scp":
    if auth not in ("password", "key", "agent"):
        raise SystemExit(
            f"deploy.json: domains.{domain}.scp.auth must be password, key or agent"
        )
    if auth == "password":
        required("password")
    elif auth == "key":
        required("identity_file")
else:
    raise SystemExit(f"deploy.json: unsupported transport: {transport}")

values = {
    "TRANSPORT_HOST": str(host),
    "TRANSPORT_PORT": str(port),
    "TRANSPORT_USER": str(user),
    "TRANSPORT_PASSWORD": str(password),
    "TRANSPORT_AUTH": str(auth),
    "TRANSPORT_IDENTITY_FILE": str(identity_file),
    "TRANSPORT_REMOTE_ROOT": str(remote_root),
    "DEPLOY_OVERWRITE_DEFAULT": "true" if overwrite_default else "false",
}

for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY
    )"; then
        return 1
    fi

    eval "${assignments}"

    if [[ "${TRANSPORT_IDENTITY_FILE}" == "~/"* ]]; then
        TRANSPORT_IDENTITY_FILE="${HOME}/${TRANSPORT_IDENTITY_FILE#~/}"
    fi
}
