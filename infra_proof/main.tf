terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.22"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "cluster_name" {
  type    = string
  default = "orders-eks-cluster"
}

resource "random_pet" "id" {
  length = 2
}

locals {
  name_prefix = "${var.cluster_name}-${random_pet.id.id}"
  public_cidr = "10.0.0.0/16"
}

# VPC & subnets

resource "aws_vpc" "main" {
  cidr_block = local.public_cidr
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name_prefix}-igw" }
}

# Public subnets (2 AZs)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${local.name_prefix}-pub-a" }
}
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "${local.name_prefix}-pub-b" }
}

# Private subnets (for EKS nodes / DB)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "${local.name_prefix}-priv-a" }
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "${local.name_prefix}-priv-b" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security groups

resource "aws_security_group" "ec2_sg" {
  name   = "${local.name_prefix}-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ec2-sg" }
}

resource "aws_security_group" "eks_node_sg" {
  name   = "${local.name_prefix}-eks-nodes"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EKS IAM roles & cluster

resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = data.aws_iam_policy_document.eks_assume_policy.json
}

data "aws_iam_policy_document" "eks_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attach" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Node group role
resource "aws_iam_role" "eks_node_role" {
  name = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_policy.json
}

data "aws_iam_policy_document" "node_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "node_A" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_B" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "node_C" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  # minimal config
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_attach
  ]
}

resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${local.name_prefix}-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  instance_types = ["t3.micro"]

  depends_on = [
    aws_eks_cluster.eks
  ]
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.eks.name
}

# Kubernetes Hello (express-like) deployment

resource "kubernetes_namespace" "app" {
  metadata {
    name = "orders-app"
  }
}

resource "kubernetes_deployment" "hello" {
  metadata {
    name = "hello-world"
    labels = {
      app = "hello-world"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hello-world"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }

      spec {
        container {
          name  = "hello-world"
          image = "nginxdemos/hello"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "hello_svc" {
  metadata {
    name      = "hello-node-svc"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  spec {
    selector = {
      app = kubernetes_deployment.hello.spec[0].template[0].metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}

# EC2 Instance with Postgres + seeding

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "random_password" "pg_password" {
  length  = 16
  special = false
}

resource "aws_instance" "old_ec2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.small"
  subnet_id     = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags = { Name = "${local.name_prefix}-old-ec2" }

  # user_data installs postgres, creates DB, schema and inserts random data
  user_data = <<-EOF
    #!/bin/bash
    set -e
    yum update -y
    amazon-linux-extras install -y postgresql10
    yum install -y postgresql-server postgresql-contrib
    # initdb & start
    /usr/bin/postgresql-setup --initdb
    systemctl enable postgresql
    systemctl start postgresql

    # Configure postgres to accept remote connections (for demo only)
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /var/lib/pgsql/data/postgresql.conf
    echo "host all all 0.0.0.0/0 trust" >> /var/lib/pgsql/data/pg_hba.conf
    systemctl restart postgresql

    # create user and DB
    sudo -u postgres psql -c "CREATE USER tfuser WITH PASSWORD '${random_password.pg_password.result}';"
    sudo -u postgres psql -c "CREATE DATABASE orders_db OWNER tfuser;"

    # create schema & seed data
    sudo -u postgres psql -d orders_db <<'PSQL'
    -- Tables as per the diagram
    CREATE TABLE "User" (
      idUser SERIAL PRIMARY KEY,
      name VARCHAR(100),
      lastName VARCHAR(100)
    );

    CREATE TABLE "Item" (
      idItem SERIAL PRIMARY KEY,
      itemName VARCHAR(200)
    );

    CREATE TABLE "Order" (
      idOrder SERIAL PRIMARY KEY,
      deliveryAddress TEXT,
      price NUMERIC(10,2)
    );

    CREATE TABLE "UserOrders" (
      idUser INT REFERENCES "User"(idUser),
      idOrder INT REFERENCES "Order"(idOrder),
      PRIMARY KEY (idUser, idOrder)
    );

    CREATE TABLE "OrderItems" (
      idOrder INT REFERENCES "Order"(idOrder),
      idItems INT REFERENCES "Item"(idItem),
      quantity INT,
      PRIMARY KEY (idOrder, idItems)
    );

    -- insert seed users
    INSERT INTO "User"(name, lastName) VALUES
      ('Alice','Gomez'),
      ('Bob','Martinez'),
      ('Carla','Perez');

    -- insert sample items
    INSERT INTO "Item"(itemName) VALUES
      ('Widget A'),
      ('Widget B'),
      ('Gadget X');

    -- insert sample orders and relations
    INSERT INTO "Order"(deliveryAddress, price) VALUES
      ('123 Main St', 34.90),
      ('456 Market Ave', 12.50),
      ('789 Elm St', 99.99);

    -- link users to orders
    INSERT INTO "UserOrders"(idUser, idOrder) VALUES
      (1,1),(2,2),(3,3);

    -- order items
    INSERT INTO "OrderItems"(idOrder, idItems, quantity) VALUES
      (1,1,2),(1,2,1),(2,2,5),(3,3,1);

    PSQL

    # create a simple dump file (for demonstration)
    sudo -u postgres pg_dump -Fc orders_db -f /home/ec2-user/orders_db.dump

    # make the dump world-readable (demo only)
    chmod 644 /home/ec2-user/orders_db.dump
  EOF

  # allow enough time for user_data to finish before snapshotting
  provisioner "local-exec" {
    command = "echo EC2 instance created: ${self.public_ip}"
  }
}

# wait for instance creation then make ami
resource "aws_ami_from_instance" "old_ec2_ami" {
  name               = "${local.name_prefix}-old-ec2-ami"
  source_instance_id = aws_instance.old_ec2.id
  depends_on         = [aws_instance.old_ec2]
  lifecycle {
    create_before_destroy = true
  }
}

# S3 bucket for backups (simple)

resource "aws_s3_bucket" "db_backups" {
  bucket = "${local.name_prefix}-db-backups-${random_pet.id.id}"
  tags = {
    Name = "${local.name_prefix}-db-backups"
  }
}

resource "aws_iam_role" "s3_backup_role" {
  name = "${local.name_prefix}-s3-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_backup_policy" {
  name = "${local.name_prefix}-s3-policy"
  role = aws_iam_role.s3_backup_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject","s3:GetObject","s3:ListBucket"],
        Resource = [aws_s3_bucket.db_backups.arn, "${aws_s3_bucket.db_backups.arn}/*"]
      }
    ]
  })
}


# Outputs
output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "hello_service_hostname" {
  description = "LoadBalancer hostname for the hello-node service (may take a minute)."
  value       = kubernetes_service.hello_svc.status[0].load_balancer[0].ingress[0].hostname
  depends_on  = [kubernetes_service.hello_svc]
}

output "old_ec2_public_ip" {
  value = aws_instance.old_ec2.public_ip
}

output "postgres_user" {
  value = "tfuser"
}

output "postgres_password" {
  value = random_password.pg_password.result
  sensitive = true
}

output "old_ec2_ami_id" {
  value = aws_ami_from_instance.old_ec2_ami.id
}
