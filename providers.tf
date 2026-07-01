terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Memaksa Terraform menggunakan path-style URL (http://localhost:4566/bucket-name)
  # daripada virtual-hosted style (http://bucket-name.localhost:4566) yang sering memicu hang di CI
  s3_use_path_style           = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}
