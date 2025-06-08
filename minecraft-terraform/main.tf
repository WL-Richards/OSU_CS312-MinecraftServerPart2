# Required dependencies and versions
#--------------------------------------------------------------------------------
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # Used to communicate with aws
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }

    # Used to generate our SSH keys
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Used to store the resulting keys locally on our machine
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
#--------------------------------------------------------------------------------

# Setup aws provider with creds file
#--------------------------------------------------------------------------------
provider "aws" {
  region = "us-west-2"
  shared_credentials_files = ["../.aws/credentials"]
}
#--------------------------------------------------------------------------------

# Utilize default VPC
#--------------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}
#--------------------------------------------------------------------------------

# Utilize default subnets
#--------------------------------------------------------------------------------
data "aws_subnets" "default_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
#--------------------------------------------------------------------------------

# Generate new SSH key to handle connections
#--------------------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
#--------------------------------------------------------------------------------

# Request a new keypair generated from our previously generated private key
#--------------------------------------------------------------------------------
resource "aws_key_pair" "generated" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}
#--------------------------------------------------------------------------------

# Write the resulting private key file to the local disk and set its permissions so we are able to execute it
#--------------------------------------------------------------------------------
resource "local_file" "private_key_pem" {
  filename        = "${path.module}/id_${var.project_name}.pem"
  file_permission = "0600"
  content         = tls_private_key.ssh.private_key_pem
}
#--------------------------------------------------------------------------------


# Setup our security group for this instance, allow connections on port 22 for SSH and connections on port 25565 for the minecraft server and allow all outbound connections
#--------------------------------------------------------------------------------
resource "aws_security_group" "mc_sg" {
  name_prefix = "${var.project_name}-sg"
  description = "Allow SSH and Minecraft"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#  Set the machine image to the Latest Amazon Linux 2023 AMI (64-bit)
#--------------------------------------------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
#--------------------------------------------------------------------------------

# EC2 Instance created with enough memory to support the server
#--------------------------------------------------------------------------------
resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default_public.ids[0]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name
  vpc_security_group_ids      = [aws_security_group.mc_sg.id]

  # Allocate some arbitrary amount of disk space
  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  # Give our instance a name
  tags = {
    Name = "${var.project_name}"
  }

  # Install and setup the docker container over the SSH connection,
  # Here we configure the docker container to run as a deamon and automatically restart using the --restart unless-stopped command also mounting the world data outside of the container 
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum -y install docker",
      "sudo systemctl enable --now docker",
      "sudo mkdir -p /opt/minecraft",
      "sudo /usr/bin/docker run -d --name minecraft -e EULA=TRUE -p 25565:25565 -v /opt/minecraft:/data --restart unless-stopped itzg/minecraft-server:latest"
    ]
    
    # Specifiy the connection details
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ssh.private_key_pem
      host        = self.public_ip
    }
  }
}
#--------------------------------------------------------------------------------