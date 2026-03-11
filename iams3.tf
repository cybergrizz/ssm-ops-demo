resource "aws_iam_role_policy" "ssm_s3_logs" {
  name = "ssm-s3-log-upload"
  role = aws_iam_role.role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SSMLogUpload"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::ssm-demo-bucket/ssm-log-collections/*"
      },
      {
        Sid      = "SSMGetEncryption"
        Effect   = "Allow"
        Action   = ["s3:GetEncryptionConfiguration"]
        Resource = "arn:aws:s3:::ssm-demo-bucket"
      }
    ]
  })
}
