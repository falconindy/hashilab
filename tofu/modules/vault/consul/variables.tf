variable "consul_address" {
  description = "Consul HTTP API address (host:port, no scheme) the engine uses to mint/revoke child tokens. Deployment-specific: required, no default."
  type        = string
}
