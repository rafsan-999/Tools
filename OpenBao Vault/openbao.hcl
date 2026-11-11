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