variable "public_key_path" {
  description = <<DESCRIPTION
Path to the SSH public key to be used for authentication.
Ensure this keypair is added to your local SSH agent so provisioners can
connect.

Example: ~/.ssh/terraform.pub
DESCRIPTION
}

variable "key_name" {
  description = "Desired name of AWS key pair"
}

variable "aws_region" {
  description = "AWS Mumbai region to launch servers."
  default     = "ap-south-1"
}

# Ubuntu Server 20.04 LTS (HVM), SSD Volume Type  (x64)
variable "aws_amis" {
  default = {
    us-east-1 = "ami-00399ec92321828f5 "
  }
}
