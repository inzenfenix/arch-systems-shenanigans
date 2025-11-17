resource "aws_vpc" "main" {
cidr_block = var.vpc_cidr
enable_dns_support = true
enable_dns_hostnames = true
tags = {
Name = "${var.project_name}-vpc"
}
}


resource "aws_internet_gateway" "igw" {
vpc_id = aws_vpc.main.id
tags = {
Name = "${var.project_name}-igw"
}
}


# Public subnets
data "aws_availability_zones" "available" {}


resource "aws_subnet" "public" {
count = length(var.public_subnet_cidrs)
vpc_id = aws_vpc.main.id
cidr_block = var.public_subnet_cidrs[count.index]
availability_zone = data.aws_availability_zones.available.names[count.index]
map_public_ip_on_launch = true


tags = {
Name = "${var.project_name}-public-${count.index}"
}
}


# Private subnets
resource "aws_subnet" "private" {
count = length(var.private_subnet_cidrs)
vpc_id = aws_vpc.main.id
cidr_block = var.private_subnet_cidrs[count.index]
availability_zone = data.aws_availability_zones.available.names[count.index]


tags = {
Name = "${var.project_name}-private-${count.index}"
}
}


# NAT Gateway (1 for simplicity)
resource "aws_eip" "nat" {
vpc = true
tags = {
Name = "${var.project_name}-nat-eip"
}
}


resource "aws_nat_gateway" "nat" {
allocation_id = aws_eip.nat.id
subnet_id = aws_subnet.public[0].id


tags = {
Name = "${var.project_name}-nat"
}
}


# Route tables (public + private)
resource "aws_route_table" "public" {
vpc_id = aws_vpc.main.id


route {
cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.igw.id
}


tags = {
Name = "${var.project_name}-public-rt"
}
}


resource "aws_route_table_association" "public_assoc" {
count = length(aws_subnet.public)
subnet_id = aws_subnet.public[count.index].id
route_table_id = aws_route_table.public.id
}