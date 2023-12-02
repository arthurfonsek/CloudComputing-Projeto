output "web_public_ip" {
    description = "The public IP address of the web server"
    value = aws_eip.nat_elastic_ip.public_ip
    depends_on = [aws_eip.nat_elastic_ip]
}

output "web_public_dns" {
    description = "The public DNS address of the web server"
    value = aws_eip.nat_elastic_ip.public_dns
    depends_on = [aws_eip.nat_elastic_ip]
}

output "database_endpoint"{
    description = "The endpoint of the database"
    value = aws_db_instance.my_db_instance.endpoint
}

output "database_port"{
    description = "The port of the database"
    value = aws_db_instance.my_db_instance.port
}

output "application_url"{
    description = "CLIQUE AQUI PARA TESTAR A APLICAÇÃO"
    value = "http://${aws_lb.my_lb.dns_name}/docs"
}
