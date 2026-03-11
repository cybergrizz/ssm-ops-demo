resource "aws_vpc" "sso-demo-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "ssm_demo_subnet" {
  vpc_id            = aws_vpc.sso-demo-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "ssm-demo-subnet"
  }
}

resource "aws_internet_gateway" "ssm_demo_igw" {
  vpc_id = aws_vpc.sso-demo-vpc.id

  tags = {
    Name = "ssm-demo-igw"
  }
}

resource "aws_route_table" "ssm_demo_rt" {
  vpc_id = aws_vpc.sso-demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ssm_demo_igw.id
  }
}

resource "aws_route_table_association" "ssm_demo_rta" {
  subnet_id      = aws_subnet.ssm_demo_subnet.id
  route_table_id = aws_route_table.ssm_demo_rt.id
}