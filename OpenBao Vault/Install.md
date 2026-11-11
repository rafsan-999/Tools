# OpenBao Vault

OpenBao server running in Docker with Raft storage, deployed via Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- An external Docker network named `microcube-net`

## Setup

1. Create the required directories:

   ```bash
   sudo mkdir -p /opt/openbao/config
   sudo mkdir -p /opt/openbao/logs
   cd /opt/openbao
   ```

2. Add the config file at `/opt/openbao/config/openbao.hcl`:

   ```hcl
   ui = true
   disable_mlock = true
   api_addr = "http://10.10.101.10:8200"
   cluster_addr = "http://10.10.101.10:8201"

   storage "raft" {
     path    = "/openbao/data"
     node_id = "openbao-01"
   }

   listener "tcp" {
     address         = "0.0.0.0:8200"
     cluster_address = "0.0.0.0:8201"
     tls_disable     = true
   }
   log_level = "info"
   ```

3. Add the Compose file at `/opt/openbao/docker-compose.yaml`:

   ```yaml
   services:
     openbao:
       image: quay.io/openbao/openbao:2.7.2
       container_name: openbao
       hostname: openbao
       restart: unless-stopped
       command: server -config=/openbao/config/openbao.hcl
       ports:
         - "8200:8200"
       cap_add:
         - IPC_LOCK
       volumes:
         - ./config:/openbao/config:ro
         - ./data:/openbao/data
         - ./logs:/openbao/logs

       healthcheck:
         test:
           - CMD
           - wget
           - --spider
           - -q
           - "http://127.0.0.1:8200/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200"
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 20s

       networks:
         - microcube-net
   networks:
     microcube-net:
       external: true
   ```

4. Start the container:

   ```bash
   sudo docker compose up -d
   ```

5. Check that it's running:

   ```bash
   sudo docker ps
   sudo docker logs -f openbao
   ```

## Initialize and Unseal

Initialize OpenBao (generates the root token and unseal keys — save these securely):

```bash
sudo docker exec -it openbao bao operator init \
  -key-shares=3 \
  -key-threshold=3
```

Unseal the vault (repeat with a different key until the threshold is met):

```bash
sudo docker exec -it openbao bao operator unseal
```

Check status:

```bash
sudo docker exec openbao bao status
```

## Configuration Notes

- `api_addr` / `cluster_addr` in the config above are set to `10.10.101.10` — update these to match your host's address.
- TLS is disabled (`tls_disable = true`); place OpenBao behind a reverse proxy or enable TLS directly for production use.
- The UI is available at `http://<host>:8200/ui` once unsealed.
