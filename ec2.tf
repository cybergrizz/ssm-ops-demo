resource "aws_instance" "sso-demo-system-manager" {
  ami                         = "resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.ssm_demo_subnet.id
  iam_instance_profile        = aws_iam_instance_profile.ss-demo-profile.name
  associate_public_ip_address = true

  tags = {
    Name          = "ssm-demo-instance"
    "Patch Group" = "AmazonLinux2-Standard"
  }
}
