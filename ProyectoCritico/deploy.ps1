param(
    [switch]$AutoApprove
)

Write-Host "Packaging lambda..."
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location $root
if(Test-Path '.\terraform\lambda_function.zip'){ Remove-Item '.\terraform\lambda_function.zip' -Force }
Compress-Archive -Path '.\lambda\lambda_function.py' -DestinationPath '.\terraform\lambda_function.zip'

Write-Host "Running Terraform..."
Set-Location -LiteralPath '.\terraform'
terraform init
if($AutoApprove){
    terraform apply -auto-approve
} else {
    terraform plan -out plan.tfplan
    terraform apply "plan.tfplan"
}

Pop-Location
Write-Host "Done."
