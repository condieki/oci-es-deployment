resource "tls_private_key" "ssh_key" {
  count     = var.ssh_public_key == "" && var.ssh_private_key_path == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key" {
  count           = var.ssh_public_key == "" && var.ssh_private_key_path == "" ? 1 : 0
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = "${path.module}/generated_ssh_key.pem"
  file_permission = "0600"
}
