variable "project_name" {
description = "Prefix"
type = string
default = "orders-lab"
}

variable "vpc_id" {
  type = string
}

variable "private_eks_subnet_ids" {
  type = list(string)
}

variable "private_db_subnet_id" {
    type = string
}