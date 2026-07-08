# Project 3.6 — Terraform CI/CD: Auto Plan and Apply with LocalStack

This repository contains a production-ready automated CI/CD pipeline for managing Infrastructure as Code (IaC) using Terraform, GitHub Actions, and LocalStack. The configuration acts as a reliable quality gate and deployment engine, ensuring code compliance and automated infrastructure provisioning without human intervention.

---

## 📋 Problem Statement
Manually running `terraform plan` and `terraform apply` from a local engineer's machine introduces several severe operational risks:
* **Human Error:** Accidentally applying broken configurations or executing plans on the wrong environment.
* **Lack of Visibility:** Reviewers cannot easily see what infrastructural changes a Pull Request (PR) will introduce without checking out the branch and running commands locally.
* **Security Risks:** Hardcoding AWS Access Keys and Secret Keys into local environments or CI platforms exposes credentials to leakage.
* **Code Inconsistency:** Inconsistent code formatting (`terraform fmt`) makes team collaboration chaotic and tracking changes difficult.

---

## 🎯 Approach & Solution
To solve these problems, we built a fully decoupled GitOps-driven CI/CD pipeline using two synchronized GitHub Actions workflows:
1. **Continuous Integration (CI) Gates:** Triggered on Pull Requests to `main`. It automatically formats code, validates syntax, generates an execution plan, and comments the plan directly onto the PR discussion for reviewer visibility.
2. **Continuous Deployment (CD) Engine:** Triggered when a PR is merged into `main`. It boots a secure, mock AWS environment using LocalStack and safely applies the approved infrastructural changes automatically.

---

## 🗺️ Architecture Diagram
Below is the continuous workflow mapping out how code moves from a local machine through the automated quality controls into our environment:

```text
[ Developer Machine ] 
       │
       ▼ (git push / Open PR)
┌────────────────────────────────────────────────────────────────────────┐
│                        GITHUB ACTIONS (CI Pipeline)                    │
│                                                                        │
│ 🛠️  Setup Terraform ──> 🖌️  Check Format ──> 🤖 Validate Syntax         │
│                                                                        │
│                       🚀 Generate Plan                                 │
│                               │                                        │
│                               ▼                                        │
│         💬 Auto-Comment Terraform Plan on PR Discussion                │
└────────────────────────────────────────────────────────────────────────┘
       │
       ▼ (PR Review & Merge to main)
┌────────────────────────────────────────────────────────────────────────┐
│                        GITHUB ACTIONS (CD Pipeline)                    │
│                                                                        │
│ 🐋 Start LocalStack (v2.1.0) ──> ⚙️  Init ──> 🚀 Auto-Apply Changes     │
└────────────────────────────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                                     [ 📦 Mock AWS S3 Bucket Created ]

```

---

## 🛠️ Tech Stack & Justification

| Tool | Selection Justification |
| --- | --- |
| **Terraform (v1.5.7)** | Standard Infrastructure as Code (IaC) tool used to safely declare cloud resources deterministically and manage infrastructure state reliably. |
| **GitHub Actions** | Built-in automation platform eliminating the overhead of managing separate CI/CD servers (e.g., Jenkins). Free for public repositories. |
| **LocalStack (v2.1.0)** | Provides a localized, high-fidelity mock cloud setup of actual AWS services, ensuring tests cost $0 and can run seamlessly inside isolated CI runner environments. |
| **Docker** | Used to instantly spin up the LocalStack environment inside the GitHub runner environment via lightweight containerization. |

---

## 🧠 Lessons Learned & Troubleshooting

During construction, we faced and overcame several real-world DevOps bottlenecks:

1. **GitHub Service Containers Timeout:**
* *What failed:* Using the default GitHub Actions `services` block to spin up LocalStack caused intermittent crashes (`One or more containers failed to start`).
* *Why:* The container health checks blocked the execution stream before LocalStack was fully ready.
* *The Fix:* We converted the execution into a dedicated step running a custom `docker run` shell script with a proactive health-check loop (`until curl ... available`).


2. **LocalStack Network Isolation Hangs:**
* *What failed:* `terraform apply` got permanently stuck at `Still creating...` for several minutes until hitting the CI limits.
* *Why:* The runner machine and the Docker container were operating on isolated network planes, keeping ports obscured from Terraform.
* *The Fix:* Implemented the `--network=host` flag on the container run, exposing LocalStack's port `4566` natively to the host.


3. **AWS S3 Virtual-Hosted Path Clashes:**
* *What failed:* S3 bucket creations still hung even with matching networks.
* *Why:* The modern AWS Provider uses virtual-hosted style paths (`bucket.localhost`), causing routing loops inside mock environments.
* *The Fix:* Configured `s3_use_path_style = true` explicitly inside `providers.tf` to force predictable endpoint mapping (`localhost:4566/bucket`).



---

## 💾 Project Scripts & Code

### 1. `providers.tf`

This file connects Terraform to the LocalStack testing mock environment using safe bypasses and strict path styling.

```hcl
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

  # Essential for LocalStack to route S3 requests without DNS hangs
  s3_use_path_style           = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}

```

### 2. `main.tf`

Defines our sample infrastructure component.

```hcl
resource "aws_s3_bucket" "cicd_bucket" {
  bucket = "my-terraform-cicd-test-bucket"

  tags = {
    Environment = "Dev"
    Project     = "Terraform-CICD"
  }
}

```

### 3. `.github/workflows/terraform-ci.yml`

Runs automatically on Pull Requests to validate code formatting and post the execution layout as a comment on the PR.

```yaml
name: "Terraform CI"

on:
  pull_request:
    branches:
      - main

permissions:
  pull-requests: write
  contents: read

jobs:
  terraform-ci:
    name: "Terraform Lint, Validate and Plan"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.5.7"

      - name: Terraform Format Check
        run: terraform fmt -check

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate -no-color

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -out=tfplan
          terraform show -no-color tfplan > plan_output.txt
        continue-on-error: true

      - name: Update Pull Request Comment
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const fs = require('fs');
            let planOutput = 'No plan output found.';
            if (fs.existsSync('plan_output.txt')) {
              planOutput = fs.readFileSync('plan_output.txt', 'utf8');
            }

            const output = `#### Terraform Format and Style 🖌
            #### Terraform Initialization ⚙️
            #### Terraform Validation 🤖
            #### Terraform Plan 🚀
            
            \`\`\`terraform
            ${planOutput}
            \`\`\`
            
            *Pushed by: @${context.actor}, Action: \`${context.eventName}\`*`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

```

### 4. `.github/workflows/terraform-cd.yml`

Fires on merges to `main`. Spins up LocalStack v2.1.0 using deterministic host routing and safely auto-applies changes.

```yaml
name: "Terraform CD"

on:
  push:
    branches:
      - main

jobs:
  terraform-cd:
    name: "Terraform Apply"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.5.7"

      - name: Start LocalStack (v2.1.0)
        run: |
          docker run -d --name localstack --network=host localstack/localstack:2.1.0
          
          echo "Waiting for LocalStack v2.1.0 to boot..."
          until curl -s http://localhost:4566/_localstack/health | grep -q '"s3": "available"\|"s3": "running"'; do
            sleep 3
          done
          echo "LocalStack v2.1.0 is healthy and responding!"

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Apply
        run: timeout 120s terraform apply -auto-approve -no-color

```

---

## 🔒 Enterprise Production Extensions

### 1. AWS Authentication using OIDC (OpenID Connect)

To replicate this setup securely in production without long-lived credentials stored in GitHub secrets, utilize OpenID Connect (OIDC).

1. Configure an **Identity Provider** inside AWS IAM targeting `https://token.actions.githubusercontent.com`.
2. Define an **IAM Role** granting a narrow Trust Policy allowance:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        "StringLike": { "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORGANIZATION/YOUR_REPO:*" }
      }
    }
  ]
}

```

3. Update workflow permissions to request short-lived connection keys dynamically:

```yaml
permissions:
  id-token: write
  contents: read

```

### 2. Guardrails: Manual Environment Approvals

To secure target high-value assets (Production clusters):

1. Navigate to your repository **Settings** > **Environments** > Create an environment named `production`.
2. Enable **Required reviewers** to mandate targeted signatures before application steps trigger.
3. Reference the environment within the CD deployment declaration:
