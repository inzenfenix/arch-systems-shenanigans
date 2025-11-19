#VPC Creation
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}
#Subnets
resource "aws_subnet" "public_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[0]
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.project_name}-pub-a-subnet"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[1]
  availability_zone = "us-east-1b"

  tags = {
    Name = "${var.project_name}-pub-b-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[0]

  tags = {
    Name = "${var.project_name}-db-subnet"
  }
}

resource "aws_subnet" "private_backend_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[1]
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.project_name}-backend-a-subnet"
  }
}

resource "aws_subnet" "private_backend_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[2]
  availability_zone = "us-east-1b"

  tags = {
    Name = "${var.project_name}-backend-b-subnet"
  }
}

#Internet Gateway for public subnets
resource "aws_internet_gateway" "orders_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-main-igw"
  }
}

resource "aws_route_table" "public_snet_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.orders_igw.id
  } 

  tags = {
    Name = "${var.project_name}-pub-route"
  }
}

resource "aws_route_table_association" "public_snet_a_route_ascctn" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_snet_route.id
}

resource "aws_route_table_association" "public_snet_b_route_ascctn" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_snet_route.id
}

#NAT Gateway + Route Table for private Subnets

#US-EAST-1A
resource "aws_eip" "nat_a" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
}

resource "aws_route_table" "private_snet_bken_a_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  } 

  tags = {
    Name = "${var.project_name}-priv-nat-route"
  }
}

resource "aws_route_table_association" "private_snet_a_route_ascctn" {
  subnet_id = aws_subnet.private_backend_a.id
  route_table_id = aws_route_table.private_snet_bken_a_route.id
}

#US-EAST-1B
resource "aws_eip" "nat_b" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
}

resource "aws_route_table" "private_snet_bken_b_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  } 

  tags = {
    Name = "${var.project_name}-priv-nat-route"
  }
}

resource "aws_route_table_association" "private_snet_b_route_ascctn" {
  subnet_id = aws_subnet.private_backend_b.id
  route_table_id = aws_route_table.private_snet_bken_b_route.id
}