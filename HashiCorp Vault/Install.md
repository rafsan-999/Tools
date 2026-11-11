# HashiCorp Vault — Docker Install Guide

Self-hosted HashiCorp Vault using the Raft integrated storage backend, running as a single node in Docker Compose.

## Prerequisites

- A Linux host with Docker and the Docker Compose plugin installed
- An existing Docker network named `microcube-net` (create one if it doesn't exist: `docker network create microcube-net`), or edit `docker-compose.yaml` to use your own network
- Root/sudo access on the host

## 1. Disable swap

Vault holds secrets in memory and should never be swapped to disk.

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

## 2. Create the directory layout

```bash
sudo mkdir -p /opt/vault/{config,data,logs}
cd /opt/vault
sudo chown -R 100:1000 /opt/vault/data /opt/vault/logs
```

`100:1000` matches the `vault` user/group baked into the official `hashicorp/vault` image, so the container can write to `data` and `logs`.

## 3. Add the configuration files

`/opt/vault/config/vault.hcl`:

```hcl
ui            = true
disable_mlock = true   # recommended with Raft storage; swap is disabled on the host instead

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
log_level = "info"
```

> `tls_disable = true` is only acceptable because the listener is bound to `127.0.0.1`. If you expose Vault beyond localhost, enable TLS on the listener first.

`/opt/vault/docker-compose.yaml`:

```yaml
services:
  vault:
    image: hashicorp/vault:1.18.3   # pin a specific version; check releases for the latest
    container_name: vault
    restart: unless-stopped
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
    ports:
      - "127.0.0.1:8200:8200"     # localhost only; change to a private IP if needed
    environment:
      VAULT_ADDR: "http://127.0.0.1:8200"
      VAULT_API_ADDR: "http://127.0.0.1:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - ./config:/vault/config:ro
      - ./data:/vault/data
      - ./logs:/vault/logs
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8200/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    networks:
      - microcube-net
networks:
  microcube-net:
    external: true
```

> The original image tag `hashicorp/vault:2.2` does not correspond to a real Vault release — Vault's current release line is `1.x`. Pin an actual version (check the [Vault release notes](https://releases.hashicorp.com/vault/) for the latest) instead of using `latest`, so upgrades are deliberate.

## 4. Start Vault

```bash
docker compose up -d
docker compose logs -f vault
```

## 5. Initialize Vault

Run this **once**, on a fresh Vault with empty `data/`:

```bash
docker compose exec vault vault operator init -key-shares=5 -key-threshold=3
```

This generates 5 unseal keys (any 3 of which can unseal Vault) and the initial root token.

**Save the 5 unseal keys and the root token somewhere safe and offline (e.g., a password manager split across trusted people). They are shown only once and cannot be recovered.**

## 6. Unseal Vault

Vault starts sealed after every restart. Unseal it with any 3 of the 5 distinct keys from step 5:

```bash
docker compose exec vault vault operator unseal
docker compose exec vault vault operator unseal
docker compose exec vault vault operator unseal
docker compose exec vault vault status
```

`vault status` should report `Sealed: false`.

## 7. Log in as root

```bash
docker compose exec vault vault login
# paste the root token
```

## 8. Create an admin policy and user, then retire the root token

Create `/opt/vault/config/admin.hcl`:

```hcl
path "*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}
```

Write the policy into Vault:

```bash
docker compose exec vault vault policy write admin /vault/config/admin.hcl
```

Enable the `userpass` auth method (skip if already enabled):

```bash
docker compose exec vault vault auth enable userpass
```

Create an admin user attached to the `admin` policy:

```bash
docker compose exec vault vault write auth/userpass/users/admin \
    password='CHANGE_ME_STRONG' \
    policies=admin
```

Log in as the new admin user to confirm it works, then revoke the root token so it's no longer usable day-to-day:

```bash
docker compose exec vault vault login -method=userpass username=admin
docker compose exec vault vault token revoke <root-token>
```

Keep the unseal keys from step 5 — you still need them every time Vault restarts, even after the root token is revoked.

## Notes

- Back up `/opt/vault/data` regularly; it holds the entire Raft-based secret store.
- `docker compose restart` / host reboots leave Vault **sealed** — repeat step 6 afterward.
- Consider enabling an [audit device](https://developer.hashicorp.com/vault/docs/audit) (`vault audit enable file file_path=/vault/logs/audit.log`) for a durable record of all requests.
