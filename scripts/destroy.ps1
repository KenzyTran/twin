param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    [string]$ProjectName = "twin"
)

# Validate environment parameter
if ($Environment -notmatch '^(dev|test|prod)$') {
    Write-Host "Error: Invalid environment '$Environment'" -ForegroundColor Red
    Write-Host "Available environments: dev, test, prod" -ForegroundColor Yellow
    exit 1
}

Write-Host "Preparing to destroy $ProjectName-$Environment infrastructure..." -ForegroundColor Yellow

# Navigate to terraform directory
Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "terraform")

# Check if workspace exists
$workspaces = terraform workspace list
if (-not ($workspaces | Select-String $Environment)) {
    Write-Host "Error: Workspace '$Environment' does not exist" -ForegroundColor Red
    Write-Host "Available workspaces:" -ForegroundColor Yellow
    terraform workspace list
    exit 1
}

# Select the workspace
terraform workspace select $Environment

Write-Host "Emptying S3 buckets..." -ForegroundColor Yellow

# Get AWS Account ID for bucket names
$awsAccountId = aws sts get-caller-identity --query Account --output text

# Define bucket names with account ID
$FrontendBucket = "$ProjectName-$Environment-frontend-$awsAccountId"
$MemoryBucket = "$ProjectName-$Environment-memory-$awsAccountId"

# Empty frontend bucket if it exists
try {
    aws s3 ls "s3://$FrontendBucket" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Emptying $FrontendBucket..." -ForegroundColor Gray
        aws s3 rm "s3://$FrontendBucket" --recursive
    }
} catch {
    Write-Host "  Frontend bucket not found or already empty" -ForegroundColor Gray
}

# Empty memory bucket if it exists
try {
    aws s3 ls "s3://$MemoryBucket" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Emptying $MemoryBucket..." -ForegroundColor Gray
        aws s3 rm "s3://$MemoryBucket" --recursive
    }
} catch {
    Write-Host "  Memory bucket not found or already empty" -ForegroundColor Gray
}

Write-Host "Running terraform destroy..." -ForegroundColor Yellow

# Prepare terraform destroy command with proper argument handling
$terraformArgs = @()
$terraformArgs += "destroy"

# Add var-file if it exists for prod environment
if ($Environment -eq "prod" -and (Test-Path "prod.tfvars")) {
    $terraformArgs += "-var-file=prod.tfvars"
}

# Add variables with proper quoting
$terraformArgs += "-var=project_name=$ProjectName"
$terraformArgs += "-var=environment=$Environment"
$terraformArgs += "-auto-approve"

# Execute terraform destroy with splatting to avoid argument parsing issues
Write-Host "Executing: terraform $($terraformArgs -join ' ')" -ForegroundColor Gray
& terraform @terraformArgs

# Check if terraform destroy was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Infrastructure for $Environment has been destroyed!" -ForegroundColor Green
} else {
    Write-Host "Terraform destroy failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "  To remove the workspace completely, run:" -ForegroundColor Cyan
Write-Host "   terraform workspace select default" -ForegroundColor White
Write-Host "   terraform workspace delete $Environment" -ForegroundColor White