# Sengaja dibuat berantakan untuk tes terraform fmt
resource "aws_s3_bucket" "cicd_bucket" {
  bucket = "my-terraform-cicd-test-bucket"
  tags = {
    Environment = "Dev"
    Project     = "Terraform-CICD"
  }
}
