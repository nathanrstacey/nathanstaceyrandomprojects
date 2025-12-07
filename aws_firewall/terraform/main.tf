terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  # Read from env (AWS_REGION / AWS_DEFAULT_REGION) or override via TF_VAR_aws_region
  region = var.aws_region
}

# ------------------------------
# Variables
# ------------------------------
variable "aws_region" {
  description = "AWS region to deploy resources in"
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "Existing VPC where the lab will be deployed"
  default     = "vpc-773e7e1e"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to firewalls"
  default     = "0.0.0.0/0" # tighten later if you want
}

locals {
  tags = {
    division = "field"
    org      = "sa"
    team     = "pubsec"
    project  = "nathanstacey-firewall-lab"
  }
}

data "aws_availability_zones" "available" {}

# Use the existing Internet Gateway attached to this VPC
data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# ------------------------------
# Subnets
# ------------------------------
# client subnet: where the downloader lives
resource "aws_subnet" "client" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.100.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(local.tags, { Name = "nathanstacey-client-subnet-lab" })
}

# firewall LAN subnet (internal side of the firewalls)
resource "aws_subnet" "firewall_lan" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.101.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(local.tags, { Name = "nathanstacey-firewall-lan-subnet-lab" })
}

# FTP server subnet
resource "aws_subnet" "server1" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.102.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(local.tags, { Name = "nathanstacey-server1-subnet-lab" })
}

# public WAN subnet (external side of the firewalls)
resource "aws_subnet" "public_wan" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.103.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(local.tags, { Name = "nathanstacey-public-wan-subnet-lab" })
}

# ------------------------------
# Security Groups
# ------------------------------

# Internal firewall LAN SG
resource "aws_security_group" "firewall_lan_sg" {
  name        = "nathanstacey-firewall-lan-sg"
  description = "SG for firewall LAN interfaces"
  vpc_id      = var.vpc_id

  # allow any internal traffic within VPC
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-firewall-lan-sg-lab" })
}

# Firewall WAN SG (SSH / HTTPS / etc from your admin network)
resource "aws_security_group" "firewall_wan_sg" {
  name        = "nathanstacey-firewall-wan-sg"
  description = "SG for firewall WAN interfaces"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-firewall-wan-sg-lab" })
}

# FTP server SG
resource "aws_security_group" "server1_sg" {
  name        = "nathanstacey-server1-sg"
  description = "SG for FTP Server1"
  vpc_id      = var.vpc_id

  # FTP control channel
  ingress {
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  # Passive FTP range
  ingress {
    from_port   = 40000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  # SSH from admin for debugging (optional)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # allow from firewalls on any port
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.firewall_lan_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-server1-sg-lab" })
}

# Client / downloader SG
resource "aws_security_group" "server2_sg" {
  name        = "nathanstacey-server2-sg"
  description = "SG for client downloader (Server2)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # allow any ingress from firewall LAN if needed
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.firewall_lan_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-server2-sg-lab" })
}

# ------------------------------
# EC2 Instances (FTP + Client)
# ------------------------------

locals {
  ubuntu_ami = "ami-0f5fcdfbd140e4ab7" # Ubuntu in us-east-2 (from your previous config)
}

# FTP Server
resource "aws_instance" "server1" {
  ami                         = local.ubuntu_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.server1.id
  vpc_security_group_ids      = [aws_security_group.server1_sg.id]
  associate_public_ip_address = false
  key_name                    = "lab-key"

  tags = merge(local.tags, { Name = "nathanstacey-server1-lab" })
}

# Client / downloader
resource "aws_instance" "server2" {
  ami                         = local.ubuntu_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.client.id
  vpc_security_group_ids      = [aws_security_group.server2_sg.id]
  associate_public_ip_address = false
  key_name                    = "lab-key"

  tags = merge(local.tags, { Name = "nathanstacey-server2-lab" })
}

# ------------------------------
# Firewalls (Primary + Backup)
# ------------------------------

# Primary firewall WAN (eth0) is the instance's main NIC in public_wan
resource "aws_instance" "firewall_primary" {
  ami                         = local.ubuntu_ami
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public_wan.id
  private_ip                  = "172.31.103.10"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.firewall_wan_sg.id]
  key_name                    = "lab-key"

  # allow routing/NAT
  source_dest_check = false

  tags = merge(local.tags, { Name = "nathanstacey-firewall-primary-lab" })
}

# Primary firewall LAN ENI (eth1)
resource "aws_network_interface" "fw_primary_lan_eni" {
  subnet_id         = aws_subnet.firewall_lan.id
  private_ips       = ["172.31.101.10"]
  security_groups   = [aws_security_group.firewall_lan_sg.id]
  source_dest_check = false

  tags = merge(local.tags, { Name = "nathanstacey-fw-primary-lan-eni" })
}

resource "aws_network_interface_attachment" "fw_primary_lan_attach" {
  instance_id          = aws_instance.firewall_primary.id
  network_interface_id = aws_network_interface.fw_primary_lan_eni.id
  device_index         = 1
}

# Backup firewall WAN
resource "aws_instance" "firewall_backup" {
  ami                         = local.ubuntu_ami
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public_wan.id
  private_ip                  = "172.31.103.11"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.firewall_wan_sg.id]
  key_name                    = "lab-key"

  source_dest_check = false

  tags = merge(local.tags, { Name = "nathanstacey-firewall-backup-lab" })
}

# Backup firewall LAN ENI
resource "aws_network_interface" "fw_backup_lan_eni" {
  subnet_id         = aws_subnet.firewall_lan.id
  private_ips       = ["172.31.101.11"]
  security_groups   = [aws_security_group.firewall_lan_sg.id]
  source_dest_check = false

  tags = merge(local.tags, { Name = "nathanstacey-fw-backup-lan-eni" })
}

resource "aws_network_interface_attachment" "fw_backup_lan_attach" {
  instance_id          = aws_instance.firewall_backup.id
  network_interface_id = aws_network_interface.fw_backup_lan_eni.id
  device_index         = 1
}

# ------------------------------
# Route Tables
# ------------------------------

# Public WAN subnet -> Internet via existing IGW
resource "aws_route_table" "public_wan_rt" {
  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "nathanstacey-public-wan-rt" })
}

resource "aws_route_table_association" "public_wan_assoc" {
  subnet_id      = aws_subnet.public_wan.id
  route_table_id = aws_route_table.public_wan_rt.id
}

resource "aws_route" "public_wan_default" {
  route_table_id         = aws_route_table.public_wan_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.existing.id
}

# Firewall LAN subnet -> Internet via existing IGW (for firewall's own traffic)
resource "aws_route_table" "firewall_lan_rt" {
  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "nathanstacey-firewall-lan-rt" })
}

resource "aws_route_table_association" "firewall_lan_assoc" {
  subnet_id      = aws_subnet.firewall_lan.id
  route_table_id = aws_route_table.firewall_lan_rt.id
}

resource "aws_route" "firewall_lan_default" {
  route_table_id         = aws_route_table.firewall_lan_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.existing.id
}

# Client subnet RT: force traffic to server1 + Internet via PRIMARY firewall LAN ENI
resource "aws_route_table" "client_rt" {
  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "nathanstacey-client-rt" })
}

resource "aws_route_table_association" "client_assoc" {
  subnet_id      = aws_subnet.client.id
  route_table_id = aws_route_table.client_rt.id
}

resource "aws_route" "client_to_server1" {
  route_table_id         = aws_route_table.client_rt.id
  destination_cidr_block = aws_subnet.server1.cidr_block
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

resource "aws_route" "client_default_via_fw" {
  route_table_id         = aws_route_table.client_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

# Server1 subnet RT: force traffic to client + Internet via PRIMARY firewall LAN ENI
resource "aws_route_table" "server1_rt" {
  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "nathanstacey-server1-rt" })
}

resource "aws_route_table_association" "server1_assoc" {
  subnet_id      = aws_subnet.server1.id
  route_table_id = aws_route_table.server1_rt.id
}

resource "aws_route" "server1_to_client" {
  route_table_id         = aws_route_table.server1_rt.id
  destination_cidr_block = aws_subnet.client.cidr_block
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

resource "aws_route" "server1_default_via_fw" {
  route_table_id         = aws_route_table.server1_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

# ------------------------------
# Outputs
# ------------------------------
output "fw_primary_public_ip" {
  value = aws_instance.firewall_primary.public_ip
}

output "fw_backup_public_ip" {
  value = aws_instance.firewall_backup.public_ip
}

output "fw_primary_lan_private_ip" {
  value = aws_network_interface.fw_primary_lan_eni.private_ips[0]
}

output "fw_backup_lan_private_ip" {
  value = aws_network_interface.fw_backup_lan_eni.private_ips[0]
}

output "server1_private_ip" {
  value = aws_instance.server1.private_ip
}

output "server2_private_ip" {
  value = aws_instance.server2.private_ip
}
