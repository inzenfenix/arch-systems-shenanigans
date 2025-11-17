variable "aws_region" {
description = "AWS region to deploy into"
type = string
default = "us-east-1"
}


variable "project_name" {
description = "Prefix for naming resources"
type = string
default = "orders-lab"
}


variable "vpc_cidr" {
description = "CIDR block for the VPC"
type = string
default = "10.0.0.0/16"
}


variable "public_subnet_cidrs" {
description = "List of CIDRs for public subnets"
type = list(string)
default = ["10.0.1.0/24", "10.0.2.0/24"]
}


variable "private_subnet_cidrs" {
description = "List of CIDRs for private subnets"
type = list(string)
default = ["10.0.11.0/24", "10.0.12.0/24"]
}