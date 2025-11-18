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
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[0]

  tags = {
    Name = "${var.project_name}-pub-subnet"
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
    Name = "${var.project_name}-backend-subnet"
  }
}

resource "aws_subnet" "private_backend_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[2]
  availability_zone = "us-east-1b"

  tags = {
    Name = "${var.project_name}-backend-subnet"
  }
}

#Internet Gateway for public subnet
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

resource "aws_route_table_association" "public_snet_route_ascctn" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_snet_route.id
}