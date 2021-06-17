terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = var.aws_region
  shared_credentials_file = "/home/ubuntu/.aws/credentials"
  profile = "default"
}

resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# Create a VPC to launch our instances into
resource "aws_vpc" "corda-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "corda-vpc"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "corda-igw" {
  vpc_id = aws_vpc.corda-vpc.id
  tags = {
    Name = "corda-igw"
  }
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.corda-vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.corda-igw.id
}

# Create a subnet to launch our CENM instances into
resource "aws_subnet" "nodes-notary" {
  vpc_id                  = aws_vpc.corda-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  depends_on = [aws_internet_gateway.corda-igw]
}

# Create a subnet to launch our Corda Nodes and Notary instances into
resource "aws_subnet" "cenm" {
  vpc_id                  = aws_vpc.corda-vpc.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true

  depends_on = [aws_internet_gateway.corda-igw]
}

resource "aws_eip" "eip-cenm" {
  vpc = true
}

resource "aws_eip" "eip-nodes-notary" {
  vpc = true
}

resource "aws_eip_association" "eip_assoc-cenm" {
  instance_id   = aws_instance.cenm.id
  allocation_id = aws_eip.eip-cenm.id
}

resource "aws_eip_association" "eip_assoc-nodes" {
  instance_id   = aws_instance.corda-node-1.id
  allocation_id = aws_eip.eip-nodes-notary.id
}

resource "aws_instance" "cenm" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    type = "ssh"
    # The default username for our AMI
    user = "ubuntu"
    host = self.public_ip
    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "m5.2xlarge"

  # Lookup the correct AMI based on the region
  # we specified
  ami = var.aws_amis[var.aws_region]

  # The name of our SSH keypair we created above.
  key_name = aws_key_pair.auth.id

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.cenm-sg.id]

  subnet_id = aws_subnet.cenm.id
  private_ip = "10.0.0.75"
}

resource "aws_instance" "corda-node-1" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    type = "ssh"
    # The default username for our AMI
    user = "ubuntu"
    host = self.public_ip
    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "m5.2xlarge"

  # Lookup the correct AMI based on the region
  # we specified
  ami = var.aws_amis[var.aws_region]

  # The name of our SSH keypair we created above.
  key_name = aws_key_pair.auth.id

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.corda-sg.id]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = aws_subnet.nodes-notary.id
  private_ip = "10.0.1.9"
}

resource "aws_instance" "notary" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    type = "ssh"
    # The default username for our AMI
    user = "ubuntu"
    host = self.public_ip
    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "t2.xlarge"

  # Lookup the correct AMI based on the region
  # we specified
  ami = var.aws_amis[var.aws_region]

  # The name of our SSH keypair we created above.
  key_name = aws_key_pair.auth.id

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.corda-sg.id]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = aws_subnet.nodes-notary.id

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt install -y openjdk-8-jdk",
      "sudo update-alternatives --set java /usr/lib/jvm/jdk1.8.0_242/bin/java",
    ]
  }
}

# A security group for the Corda nodes and Notary
resource "aws_security_group" "corda-sg" {
  name        = "Corda Nodes Security Group"
  description = "Used for the Corda Nodes"
  vpc_id      = aws_vpc.corda-vpc.id

  # H2DB access
  ingress {
    description = "H2DB"
    from_port   = 12001
    to_port     = 12001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All TCP
  ingress {
    description = "All TCP allowed"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL
  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH Node
  ingress {
    description = "SSH Node access"
    from_port   = 10022
    to_port     = 10022
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Node Service
  ingress {
    description = "Node Service"
    from_port   = 50000
    to_port     = 64000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "Identity Manager"
    from_port   = 10000
    to_port     = 10000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "cenm-sg" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.corda-vpc.id

  # SSH
  ingress {
    description = "Identity Manager"
    from_port   = 5051
    to_port     = 5052
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.corda-vpc.cidr_block]
  }

  # H2DB access
  ingress {
    description = "Signer SSH"
    from_port   = 1110
    to_port     = 1110
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.corda-vpc.cidr_block]
  }

  # All TCP
  ingress {
    description = "Notary and Node 1"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.corda-vpc.cidr_block]
  }

  # SSH Node
  ingress {
    description = "SSH Identity Manager"
    from_port   = 2220
    to_port     = 2220
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH access"
    from_port   = 10022
    to_port     = 10022
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Network Map SSH
  ingress {
    description = "Network Map SSH"
    from_port   = 3330
    to_port     = 3330
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Network Map Service"
    from_port   = 20100
    to_port     = 20100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Network Map Service"
    from_port   = 10100
    to_port     = 10100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
