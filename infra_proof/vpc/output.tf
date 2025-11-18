output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_db_subnet_id" {
  value = aws_subnet.private_db.id
}

output "private_backends_subnet_id" {
  value = [aws_subnet.private_backend_a.id, aws_subnet.private_backend_b.id]
}