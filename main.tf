#Esboço inicial do projeto retirado do tutorial próprio do Terraform.

terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 4.16"
      }
    }
  
    backend "s3" {
      bucket = "arthurfonsek-bucket"
      key    = "terraform.tfstate"
      region = "us-east-1"
    }
  
    required_version = ">= 1.2.0"
  }
  
  data "aws_availability_zones" "available" {
    state = "available"
  }
  
  provider "aws" {
    region = "us-east-1"
  }
  
#-------------------Criação da VPC-------------------#
  
  resource "aws_vpc" "my_vpc" {
    cidr_block = "10.0.0.0/16" 
  
    enable_dns_support   = true
    enable_dns_hostnames = true
  
    tags = {
      Name = "arthurfonsek-vpc"
    }
  }
  
#-------------------Criação das Subnets-------------------#

#Subnets Públicas
  resource "aws_subnet" "my_subnet" {
    vpc_id                  = aws_vpc.my_vpc.id
    cidr_block              = "10.0.1.0/24" # substitua isso pelo bloco CIDR desejado para a sua subnet
    availability_zone       = "us-east-1a"  # substitua isso pela zona de disponibilidade desejada
    map_public_ip_on_launch = true
  
    tags = {
      Name = "pub-subnet"
    }
  }
  
#Subnets Privadas

  resource "aws_subnet" "my_private_subnet" {
    vpc_id            = aws_vpc.my_vpc.id
    cidr_block        = "10.0.101.0/24"
    availability_zone = "us-east-1a"
  
    tags = {
      Name = "private-subnet"
    }
  }

  resource "aws_subnet" "my_private_subnet2" {
    vpc_id            = aws_vpc.my_vpc.id
    cidr_block        = "10.0.102.0/24"
    availability_zone = "us-east-1b"
  
    tags = {
      Name = "private-subnet2"
    }
  }
  
  # INTERNET GATEWAY --------------------------------------------------------------------------------
  
  resource "aws_internet_gateway" "my_igw" {
    vpc_id = aws_vpc.my_vpc.id
  
    tags = {
      Name = "arturfonsek-igw"
    }
  }
  
  #-------------------Criação da Route Table-------------------#

  # Route Table Pública
  
  resource "aws_route_table" "my_route_table" {
    vpc_id = aws_vpc.my_vpc.id
  
    route {
      cidr_block = "0.0.0.0/0" # rota padrão para a internet
      gateway_id = aws_internet_gateway.my_igw.id
    }
  
    tags = {
      Name = "pub-route-table"
    }
  }

  # Associando a Route Table Pública à Subnet Pública
  
  resource "aws_route_table_association" "my_association" {
    subnet_id      = aws_subnet.my_subnet.id
    route_table_id = aws_route_table.my_route_table.id
  }
  

#-------------------Criação do Elastic IP-------------------#

# Elastic IP para o NAT Gateway 
  resource "aws_eip" "nat_elastic_ip" {
    depends_on = [aws_internet_gateway.my_igw]
    vpc       = true
    tags = {
      Name = "nat-elastic-ip"
    }
  }
  
#-------------------Criação dos Security Groups-------------------#
  
# Security Group para o Load Balancer
  resource "aws_security_group" "my_security_group" {
    name        = "arthurfonsek-sg"
    description = "My Security Group Description"
    vpc_id      = aws_vpc.my_vpc.id
  
    ingress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"] # Permitir tráfego SSH de qualquer lugar
    }
  
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"] # Permitir todo o tráfego de saída
    }
  
    tags = {
      Name = "sg-ssh-http-https"
    }
  }

# Security Group para o Banco de Dados
  resource "aws_security_group" "db_security_group" {
    name        = "arthurfonsek-db-sg"
    description = "My Security Group Description"
    vpc_id      = aws_vpc.my_vpc.id
  
    ingress {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      security_groups = [aws_security_group.my_security_group.id]
    }
  }
  
#-------------------Criação do Load Balancer-------------------#
  
  #
  resource "aws_lb_target_group" "my_lb_target_group" {
    health_check {
      interval            = 10
      path                = "/docs"
      protocol            = "HTTP"
      timeout             = 5
      healthy_threshold   = 5
      unhealthy_threshold = 2
    }
  
    name        = "arthurfonseklb-target-group"
    port        = 80
    protocol    = "HTTP"
    target_type = "instance"
    vpc_id      = aws_vpc.my_vpc.id
  }
  
  #Subnet publica para o load balancer atuar entre as duas subnets
  resource "aws_subnet" "my_subnet_2" {
    vpc_id                  = aws_vpc.my_vpc.id
    cidr_block              = "10.0.2.0/24"
    availability_zone       = "us-east-1b"
    map_public_ip_on_launch = true
  
    tags = {
      Name = "pub-subnet-2"
    }
  }
  
  #Associando a Route Table Pública à Subnet Pública 2
  resource "aws_route_table_association" "my_association2" {
    subnet_id      = aws_subnet.my_subnet_2.id
    route_table_id = aws_route_table.my_route_table.id
  }
  
  #Criando o Load Balancer
  resource "aws_lb" "my_lb" {
    name               = "arthurfonsek-lb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.my_security_group.id]
    subnets            = [aws_subnet.my_subnet.id, aws_subnet.my_subnet_2.id]
  
    tags = {
      Name = "arthurfonsek-lb"
    }
  }
  
  #Associando o Load Balancer com o Listener para fazer o roteamento e o forwarding para o target group
  resource "aws_lb_listener" "my_lb_listener" {
    load_balancer_arn = aws_lb.my_lb.arn
    port              = "80"
    protocol          = "HTTP"
  
    default_action {
      target_group_arn = aws_lb_target_group.my_lb_target_group.arn
      type             = "forward"
    }
  }
  
#-------------------Criação do NAT Gateway-------------------#
  
  resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat_elastic_ip.id
    subnet_id     = aws_subnet.my_subnet.id # Specify the subnet ID of the public subnet
  }
  

#-------------------Criação da Route Table Privada-------------------#
  resource "aws_route_table" "my_private_route_table" {
    vpc_id = aws_vpc.my_vpc.id
  
    route {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat.id
    }
  
    tags = {
      Name = "nat-route-table"
    }
  }

#Associando a Route Table Privada às Subnets Privadas
  
  resource "aws_route_table_association" "my_private_association" {
    subnet_id      = aws_subnet.my_private_subnet.id
    route_table_id = aws_route_table.my_private_route_table.id
  }
  
  resource "aws_route_table_association" "my_private_association2" {
    subnet_id      = aws_subnet.my_private_subnet2.id
    route_table_id = aws_route_table.my_private_route_table.id
  }
  
  
#-------------------Criação do Banco de Dados-------------------#

#Criando o Subnet Group para o Banco de Dados
  
  resource "aws_db_subnet_group" "arthurfonsek-db-subnet-group" {
    name        = "arthurfonsek-db-subnet-group"
    description = "My DB subnet group"
    subnet_ids  = [aws_subnet.my_private_subnet.id, aws_subnet.my_private_subnet2.id]
  }
  
#Criando o Banco de Dados
  resource "aws_db_instance" "my_db_instance" {
    allocated_storage      = 20
    storage_type           = "gp2"
    engine                 = "mysql"
    engine_version         = "5.7"
    instance_class         = "db.t2.micro"
    db_name                = "arthur_db"
    username               = "dbadmin"
    password               = "secretpassword"
    db_subnet_group_name   = aws_db_subnet_group.arthurfonsek-db-subnet-group.name
    vpc_security_group_ids = [aws_security_group.db_security_group.id]
    skip_final_snapshot    = true
    multi_az               = true
    backup_retention_period = 7
    backup_window = "00:00-00:30"
    maintenance_window = "Mon:01:00-Mon:03:00"
  }
  
#-------------------Criação do Launch Template e Auto Scaling Group-------------------#
  
  #Criando o Launch Template - definindo o que será executado nas instâncias
  resource "aws_launch_template" "my_launch_template" {
    name_prefix   = "arthurfonsek-launch-template"
    image_id      = "ami-0fc5d935ebf8bc3bc"
    instance_type = "t2.micro"
    #Créditos da aplicação de teste (MySQL + FastAPI + Uvicorn) -> Arthur Cisotto:  https://github.com/ArthurCisotto
    #Eu, Arthur Fonseca, adicionei apenas esse "app.log" para verificar se o script estava sendo executado
    #Conectando à instância, vi que o script foi executado e a aplicação está rodando
    user_data = base64encode(<<-EOF
      #!/bin/bash
      sudo touch app.log 
      export DEBIAN_FRONTEND=noninteractive
  
      sudo apt -y remove needrestart
      echo "fez o needrestart" >> app.log
      sudo apt-get update
      echo "fez o update" >> app.log
      sudo apt-get install -y python3-pip python3-venv git
      echo "fez o install de tudo" >> app.log
  
      # Criação do ambiente virtual e ativação
      python3 -m venv /home/ubuntu/myappenv
      echo "criou o env" >> app.log
      source /home/ubuntu/myappenv/bin/activate
      echo "ativou o env" >> app.log
  
      # Clonagem do repositório da aplicação
      git clone https://github.com/ArthurCisotto/aplicacao_projeto_cloud.git /home/ubuntu/myapp
      echo "clonou o repo" >> app.log
  
      # Instalação das dependências da aplicação
      pip install -r /home/ubuntu/myapp/requirements.txt
      echo "instalou os requirements" >> app.log
  
      sudo apt-get install -y uvicorn
      echo "instalou o uvicorn" >> app.log
   
      # Configuração da variável de ambiente para o banco de dados
      export DATABASE_URL="mysql+pymysql://dbadmin:secretpassword@${aws_db_instance.my_db_instance.endpoint}/arthur_db"
      echo "exportou o url" >> app.log
  
      cd /home/ubuntu/myapp
      # Inicialização da aplicação
      uvicorn main:app --host 0.0.0.0 --port 80 
      echo "inicializou" >> app.log
    EOF
    )
  
    network_interfaces {
      security_groups             = [aws_security_group.my_security_group.id]
      associate_public_ip_address = true
      subnet_id                   = aws_subnet.my_subnet.id
    }
  
    tag_specifications {
      resource_type = "instance"
      tags = {
        Name = "arthurfonsek-launch-template"
      }
    }
  }
  
 #Criando o Auto Scaling Group - definindo o número de instâncias 
  resource "aws_autoscaling_group" "my_autoscaling_group" {
      name             = "arthurfonsek-autoscaling-group"
      desired_capacity = 2
      min_size         = 1
      max_size         = 5
      vpc_zone_identifier = [aws_subnet.my_subnet.id]
      target_group_arns   = [aws_lb_target_group.my_lb_target_group.arn]
      launch_template {
        id      = aws_launch_template.my_launch_template.id
        version = "$Latest"
      }
        tag {
        key                 = "Name"
        value               = "arthurfonsek-autoscaling-group"
        propagate_at_launch = true
      }
  }

#-----------------Criação das Políticas para AutoScaling via CloudWatch-----------------#
  #Esse recurso aumenta o número de instâncias quando a média de CPU for maior que 70% por 1 minuto
  resource "aws_autoscaling_policy" "upscale_arthurfonsek" {
    name = "arthurfonsek-upscale"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = aws_autoscaling_group.my_autoscaling_group.name
  }
  #Esse recurso diminui o número de instâncias quando a média de CPU for menor que 10% por 1 minuto
  resource "aws_autoscaling_policy" "downscale_arthurfonsek" {
    name = "arthurfonsek-downscale"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = aws_autoscaling_group.my_autoscaling_group.name
  }

#-----------------Criação dos alarmes do CloudWatch-----------------#

  #Alarme para aumentar o número de instâncias
  resource "aws_cloudwatch_metric_alarm" "upscale_arthurfonsek_alarm"{
    alarm_name = "arthurfonsek-upscale-alarm"
    alarm_description = "Check if CPU Utilization is greater than 70%"
    namespace = "AWS/EC2"
    metric_name = "CPUUtilization"
    period = "60"
    statistic = "Average"
    threshold = "70"
    evaluation_periods = "1"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    alarm_actions = [aws_autoscaling_policy.upscale_arthurfonsek.arn]
    ok_actions = [aws_autoscaling_policy.upscale_arthurfonsek.arn]
    dimensions = {
      AutoScalingGroupName = aws_autoscaling_group.my_autoscaling_group.name
    }
    tags = {
      Name = "arthurfonsek-upscale-alarm"
    }
  }
  
  #Alarme para diminuir o número de instâncias
  resource "aws_cloudwatch_metric_alarm" "downscale_arthurfonsek_alarm"{
    alarm_name = "arthurfonsek-downscale-alarm"
    alarm_description = "Check if CPU Utilization is less than 10%"
    evaluation_periods = "1"
    period = "60"
    statistic = "Average"
    threshold = "10"
    comparison_operator = "LessThanOrEqualToThreshold"
    namespace = "AWS/EC2"
    metric_name = "CPUUtilization"
    alarm_actions = [aws_autoscaling_policy.downscale_arthurfonsek.arn]
    ok_actions = [aws_autoscaling_policy.downscale_arthurfonsek.arn]
    dimensions = {
      AutoScalingGroupName = aws_autoscaling_group.my_autoscaling_group.name
    }
    tags = {
      Name = "arthurfonsek-downscale-alarm"
    }
  }

