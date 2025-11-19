data "aws_ami" "ubuntu_2404" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

#SG + EC2 For Old DB
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for general EC2 instance"

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg"
  }
}

resource "aws_instance" "old_ec2" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "${var.project_name}-old-ec2"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    apt-get update -y

    # Install PostgreSQL 16
    apt-get install -y postgresql-16 postgresql-contrib

    # Get installed Postgres version (e.g. '16')
    PG_VER=$(ls /etc/postgresql)

    systemctl enable postgresql
    systemctl start postgresql

    # Create user and database
    sudo -u postgres psql -c "CREATE USER tfuser WITH PASSWORD '1234';"
    sudo -u postgres psql -c "CREATE DATABASE orders_db OWNER tfuser;"

    # Create schema + seed data
    sudo -u postgres psql -d orders_db << 'PSQL'
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

    INSERT INTO "User"(name, lastName) VALUES
      ('Alice','Gomez'),
      ('Bob','Martinez'),
      ('Carla','Perez');

    INSERT INTO "Item"(itemName) VALUES
      ('Widget A'),
      ('Widget B'),
      ('Gadget X');

    INSERT INTO "Order"(deliveryAddress, price) VALUES
      ('123 Main St', 34.90),
      ('456 Market Ave', 12.50),
      ('789 Elm St', 99.99);

    INSERT INTO "UserOrders"(idUser, idOrder) VALUES
      (1,1),(2,2),(3,3);

    INSERT INTO "OrderItems"(idOrder, idItems, quantity) VALUES
      (1,1,2),(1,2,1),(2,2,5),(3,3,1);
    PSQL

    # Allow remote access
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/$PG_VER/main/postgresql.conf
    echo "host    all    all    0.0.0.0/0    md5" >> /etc/postgresql/$PG_VER/main/pg_hba.conf

    systemctl restart postgresql

    # Export DB dump
    sudo -u postgres pg_dump -Fc orders_db -f /home/ubuntu/orders_db.dump
    chmod 644 /home/ubuntu/orders_db.dump
  EOF

  provisioner "local-exec" {
    command = "echo EC2 instance created: ${self.public_ip}"
  }
}

# wait for instance creation then make ami
resource "aws_ami_from_instance" "old_ec2_ami" {
  name               = "${var.project_name}-old-ec2-ami"
  source_instance_id = aws_instance.old_ec2.id
  depends_on         = [aws_instance.old_ec2]
  lifecycle {
    create_before_destroy = true
  }
}

#Database EC2 + SG

resource "aws_security_group" "ec2_sg_db" {
  name        = "${var.project_name}-ec2-db-sg"
  description = "Security group for DB EC2 instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from Admin Subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.90.0/24"]
  }

  ingress {
    description     = "Allow ingress from EKS SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-db-sg"
  }
}

resource "aws_instance" "ec2_db" {

  ami           = aws_ami_from_instance.old_ec2_ami.id
  instance_type = "t3.small"
  tags          = { Name = "${var.project_name}-db-ec2" }

  subnet_id = var.private_db_subnet_id

  vpc_security_group_ids = [
    aws_security_group.ec2_sg_db.id
  ]
}

#Bastion SG + EC2

resource "aws_security_group" "ec2_sg_bastion" {
  name        = "${var.project_name}-ec2-bastion-sg"
  description = "Security group for DB EC2 instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from Admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-bastion-sg"
  }
}

resource "aws_instance" "ec2_bastion" {

  ami           = data.aws_ami.ubuntu_2404.id
  instance_type = "t3.micro"
  tags          = { Name = "${var.project_name}-bastion-ec2" }

  subnet_id = var.public_subnet_id
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ec2_sg_bastion.id
  ]
}