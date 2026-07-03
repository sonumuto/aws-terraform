provider "aws" {
  region = "eu-central-1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"]
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-managed-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_security_group" "ec2_security_group" {
  name = "ec2_security_group"
  description = "Allow SSM access for EC2."
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "ec2_security_group"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.ec2_security_group.id
  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  to_port = 443
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id              = module.vpc.private_subnets[0]

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  tags = {
    Name = var.instance_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_from_self" {
  security_group_id            = aws_security_group.ec2_security_group.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ec2_security_group.id
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-central-1.ssm"
  security_group_ids  = [aws_security_group.ec2_security_group.id]
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-central-1.ssmmessages"
  security_group_ids  = [aws_security_group.ec2_security_group.id]
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-central-1.ec2messages"
  security_group_ids  = [aws_security_group.ec2_security_group.id]
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "example-vpc"
  cidr = "10.0.0.0/16"

  azs                  = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets       = ["10.0.101.0/24"]
  enable_dns_hostnames = true
}
