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
  region = var.aws_region
}

# ------------------------------
# Variables
# ------------------------------
variable "aws_region" {}
variable "vpc_id" {
  default = "vpc-773e7e1e"
}
variable "owner_id" {
  default = "461485115270"
}
# Optional : control SSH admin access (default open for lab)
variable "admin_cidr" {
  default = "0.0.0.0/0"
}

locals {
  tags = {
    division = "field"
    org      = "sa"
    team     = "pubsec"
    project  = "nathanstacey firewallproject"
  }
}


data "aws_availability_zones" "available" {}


resource "aws_internet_gateway" "igw" {
  # This is the imported IGW
  vpc_id = var.vpc_id
  tags   = merge(local.tags, { Name = "nathanstacey-igw" })
}


# ------------------------------
# Subnets
# ------------------------------
resource "aws_subnet" "client" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.100.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(local.tags, { Name = "nathanstacey-client-subnet-lab" })
}

resource "aws_subnet" "firewall" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.101.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(local.tags, { Name = "nathanstacey-firewall-subnet-lab" })
}

resource "aws_subnet" "server1" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.102.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(local.tags, { Name = "nathanstacey-server1-subnet-lab" })
}

resource "aws_subnet" "public_wan" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.103.0/24"  # choose a free /24 in your VPC
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = merge(local.tags, { Name = "nathanstacey-public-wan-subnet" })
}

# ------------------------------
# Security Groups
# ------------------------------
resource "aws_security_group" "firewall_sg" {
  name        = "nathanstacey-firewall-sg"
  description = "SG for UFW firewalls"
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

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Allow all TCP/UDP from internal VPC
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

  tags = merge(local.tags, { Name = "nathanstacey-firewall-sg-lab" })
}

resource "aws_security_group" "server1_sg" {
  name        = "nathanstacey-server1-sg"
  description = "SG for FTP Server1"
  vpc_id      = var.vpc_id

  # FTP control
  ingress {
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Passive FTP range
  ingress {
    from_port   = 40000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Allow the firewall SG to talk to the server on any port/proto
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.firewall_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-server1-sg-lab" })
}

resource "aws_security_group" "server2_sg" {
  name        = "nathanstacey-server2-sg"
  description = "SG for Client Downloader Server2"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "nathanstacey-server2-sg-lab" })
}

resource "aws_security_group" "firewall_wan_sg" {
  name        = "nathanstacey-firewall-wan-sg"
  description = "Firewall WAN SG"
  vpc_id      = var.vpc_id

  # SSH/HTTPS access from your admin network
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


# ------------------------------
# FTP Server1
# ------------------------------
resource "aws_instance" "server1" {
  ami                    = "ami-0f5fcdfbd140e4ab7"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.server1.id
  vpc_security_group_ids = [aws_security_group.server1_sg.id]
  associate_public_ip_address = false
  tags = merge(local.tags, { Name = "nathanstacey-server1-lab" })
}

# ------------------------------
# Client Downloader Server2
# ------------------------------
resource "aws_instance" "server2" {
  ami                    = "ami-0f5fcdfbd140e4ab7"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.client.id
  vpc_security_group_ids = [aws_security_group.server2_sg.id]
  associate_public_ip_address = false

  tags = merge(local.tags, { Name = "nathanstacey-server2-lab" })
}

# ------------------------------
# Firewall ENIs + Instances (Ubuntu + UFW)
# ------------------------------


resource "aws_network_interface" "fw_primary_wan_eni" {
  subnet_id         = aws_subnet.public_wan.id
  private_ips       = ["172.31.103.10"]
  security_groups   = [aws_security_group.firewall_wan_sg.id]
  source_dest_check = false
  tags = {
    Name = "fw-primary-wan-eni"
  }
}
resource "aws_network_interface_attachment" "fw_primary_wan_attach" {
  instance_id          = aws_instance.firewall_primary.id
  network_interface_id = aws_network_interface.fw_primary_wan_eni.id
  device_index         = 0
}


resource "aws_network_interface" "fw_backup_wan_eni" {
  subnet_id         = aws_subnet.public_wan.id
  private_ips       = ["172.31.103.11"]
  security_groups   = [aws_security_group.firewall_wan_sg.id]
  source_dest_check = false
  tags = {
    Name = "fw-backup-wan-eni"
  }
}
resource "aws_network_interface_attachment" "fw_backup_wan_attach" {
  instance_id          = aws_instance.firewall_backup.id
  network_interface_id = aws_network_interface.fw_backup_wan_eni.id
  device_index         = 0
}





resource "aws_network_interface" "fw_primary_lan_eni" {
  subnet_id       = aws_subnet.firewall.id
  source_dest_check      = false
  private_ips     = ["172.31.101.11"]
  security_groups = [aws_security_group.firewall_sg.id]
  tags = merge(local.tags, { Name = "nathanstacey-fw-primary-lan-eni" })
}



resource "aws_network_interface" "fw_backup_lan_eni" {
  subnet_id       = aws_subnet.firewall.id
  source_dest_check      = false
  private_ips     = ["172.31.101.21"]
  security_groups = [aws_security_group.firewall_sg.id]
  tags = merge(local.tags, { Name = "nathanstacey-fw-backup-lan-eni" })
}
resource "aws_network_interface_attachment" "fw_backup_lan_attach" {
  instance_id          = aws_instance.firewall_backup.id
  network_interface_id = aws_network_interface.fw_backup_lan_eni.id
  device_index         = 1
}


# EIPs for WAN ENIs so you can access UI/SSH from Internet
resource "aws_eip" "fw_primary_eip" {
  tags = merge(local.tags, { Name = "nathanstacey-fw-primary-eip" })
}

resource "aws_eip_association" "fw_primary_eip_assoc" {
  allocation_id = aws_eip.fw_primary_eip.id
  instance_id   = aws_instance.firewall_primary.id
}

resource "aws_eip" "fw_backup_eip" {
  tags = merge(local.tags, { Name = "nathanstacey-fw-backup-eip" })
}

resource "aws_eip_association" "fw_backup_eip_assoc" {
  allocation_id = aws_eip.fw_backup_eip.id
  instance_id   = aws_instance.firewall_backup.id
}

# Primary firewall Instance
resource "aws_instance" "firewall_primary" {
  ami                         = "ami-0f5fcdfbd140e4ab7"
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.firewall.id

  # Set the static WAN private IP that you originally planned for eth0
  private_ip                  = "172.31.101.10"

  # disable source/dest check on the primary instance (needed for routing)
  source_dest_check           = false

  vpc_security_group_ids      = [aws_security_group.firewall_sg.id]

  tags = merge(local.tags, { Name = "nathanstacey-firewall-primary-lab" })
}


# Attach eth1 (LAN NIC)
resource "aws_network_interface_attachment" "fw_primary_lan_attach" {
  instance_id          = aws_instance.firewall_primary.id
  network_interface_id = aws_network_interface.fw_primary_lan_eni.id
  device_index         = 1
}


# Backup firewall Instance (same as primary but with "bad ACL")
resource "aws_instance" "firewall_backup" {
  ami                         = "ami-0f5fcdfbd140e4ab7"
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.firewall.id

  # static WAN private IP for backup
  private_ip                  = "172.31.101.20"

  # disable source/dest check on the primary instance (needed for routing)
  source_dest_check           = false

  vpc_security_group_ids      = [aws_security_group.firewall_sg.id]

  tags = merge(local.tags, { Name = "nathanstacey-firewall-backup-lab" })
}



# ------------------------------
# Route Tables
# ------------------------------

# Client subnet route table
resource "aws_route_table" "client_rt" {
  vpc_id = var.vpc_id
  tags   = merge(local.tags, { Name = "nathanstacey-client-rt" })
}

resource "aws_route_table_association" "client_assoc" {
  subnet_id      = aws_subnet.client.id
  route_table_id = aws_route_table.client_rt.id
}

# Route client -> server1 via primary firewall LAN ENI
resource "aws_route" "client_to_server1" {
  route_table_id         = aws_route_table.client_rt.id
  destination_cidr_block = aws_subnet.server1.cidr_block
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

# Optional: default route via firewall WAN ENI
resource "aws_route" "client_default_via_fw" {
  route_table_id         = aws_route_table.client_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.fw_primary_wan_eni.id
}

# Server1 subnet route table
resource "aws_route_table" "server1_rt" {
  vpc_id = var.vpc_id
  tags   = merge(local.tags, { Name = "nathanstacey-server1-rt" })
}

resource "aws_route_table_association" "server1_assoc" {
  subnet_id      = aws_subnet.server1.id
  route_table_id = aws_route_table.server1_rt.id
}

# Route server1 -> client via primary firewall LAN ENI
resource "aws_route" "server1_to_client" {
  route_table_id         = aws_route_table.server1_rt.id
  destination_cidr_block = aws_subnet.client.cidr_block
  network_interface_id   = aws_network_interface.fw_primary_lan_eni.id
}

# Optional: default route via firewall WAN ENI
resource "aws_route" "server1_default_via_fw" {
  route_table_id         = aws_route_table.server1_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.fw_primary_wan_eni.id
}

# Firewall subnet route table
resource "aws_route_table" "firewall_rt" {
  vpc_id = var.vpc_id
  tags   = merge(local.tags, { Name = "nathanstacey-firewall-rt" })
}

resource "aws_route_table_association" "firewall_assoc" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall_rt.id
}

# Firewall subnet default route to internet via IGW
resource "aws_route" "firewall_default" {
  route_table_id         = aws_route_table.firewall_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# No need to declare local routes; AWS handles internal subnet routing automatically


# ------------------------------
# Outputs for convenience
# ------------------------------
output "fw_primary_wan_private_ip" {
  value = tolist(aws_network_interface.fw_primary_wan_eni.private_ips)[0]
}

output "fw_primary_lan_private_ip" {
  value = tolist(aws_network_interface.fw_primary_lan_eni.private_ips)[0]
}

output "fw_primary_eip" {
  value = aws_eip.fw_primary_eip.public_ip
}

output "fw_backup_eip" {
  value = aws_eip.fw_backup_eip.public_ip
}

output "server1_private_ip" {
  value = aws_instance.server1.private_ip
}



resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/hosts.yml.tpl", {
    server1_private_ip     = aws_instance.server1.private_ip
    server2_private_ip     = aws_instance.server2.private_ip
    fw_primary_private_ip  = aws_instance.firewall_primary.private_ip
    fw_backup_private_ip   = aws_instance.firewall_backup.private_ip
  })

  filename = "${path.module}/ansible/inventory/hosts.yml"
}