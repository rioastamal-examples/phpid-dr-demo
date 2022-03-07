terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.73.0"
    }
  }
}

# Production region (Jakarta)
provider "aws" {
  region = "${terraform.workspace == "default" ? "ap-southeast-3" : "ap-southeast-1"}"
}

data "aws_vpc" "default" {
  default = true
}

resource "random_string" "random" {
  length = 12
  special = false
  lower = true
  upper = false
}

resource "aws_security_group" "default" {
  name = "ec2-sg-${random_string.random.result}"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  
  ingress {
    description      = "Web"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [ "0.0.0.0/0" ]
  }
}

resource "aws_security_group" "elb" {
  name = "elb-sg-${random_string.random.result}"
  vpc_id = data.aws_vpc.default.id
  
  ingress {
    description      = "Web"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [ "0.0.0.0/0" ]
  }
}

resource "aws_security_group" "mysql" {
  name = "db-sg-${random_string.random.result}"
  vpc_id = data.aws_vpc.default.id
  
  ingress {
    description      = "MySQL"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.default.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [ "0.0.0.0/0" ]
  }
}

data "aws_ami" "amzn_linux2" {
  owners = ["amazon"]
  most_recent = "true"

  filter {
    name = "name"
    values = [ "amzn2-ami-kernel-*" ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh" {
  key_name = "dr-ssh"
  public_key = var.ssh_pub_key
}

data "aws_subnets" "default" {
  filter {
      name = "vpc-id"
      values = [data.aws_vpc.default.id]
  }
}

resource "aws_lb" "default" {
  name               = "lb-web"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets = data.aws_subnets.default.ids
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port = "80"
  protocol = "HTTP"
  
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

resource "aws_lb_target_group" "default" {
  name = "phpid-tg-${random_string.random.result}"
  port = "8080"
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_launch_configuration" "default" {
  name_prefix   = "phpid-lc-"
  image_id      = data.aws_ami.amzn_linux2.id
  instance_type = "${terraform.workspace == "default" ? "t3.small" : "t3.micro"}"
  security_groups = [aws_security_group.default.id]
  key_name = aws_key_pair.ssh.key_name
  user_data = file("${path.module}/scripts/userdata.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "default" {
  name                 = "phpid-asg"
  launch_configuration = aws_launch_configuration.default.name
  vpc_zone_identifier  = data.aws_subnets.default.ids
  force_delete         = true
  min_size             = 1
  max_size             = terraform.workspace == "default" ? 1 : 1
  desired_capacity     = terraform.workspace == "default" ? 1 : 1
}

# resource "aws_autoscaling_attachment" "default" {
#   autoscaling_group_name = aws_autoscaling_group.default.id
#   alb_target_group_arn = aws_lb_target_group.default.arn
# }

resource "aws_rds_cluster" "default" {
  cluster_identifier   = "phpid-aurora-cluster-${random_string.random.result}"
  engine               = "aurora-mysql"
  engine_version       = "5.7.mysql_aurora.2.10.2"
  database_name        = var.db_name
  master_username      = var.db_user
  master_password      = var.db_password
  vpc_security_group_ids = [aws_security_group.mysql.id]
  skip_final_snapshot  = true
}

resource "aws_rds_cluster_instance" "default" {
  count = terraform.workspace == "default" ? 2 : 1
  instance_class = "db.t3.medium"
  engine = aws_rds_cluster.default.engine
  engine_version = aws_rds_cluster.default.engine_version
  cluster_identifier = aws_rds_cluster.default.id
}