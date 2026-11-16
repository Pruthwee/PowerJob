@echo off & setlocal enabledelayedexpansion
rem Deploy the pushed PowerJob server image to AWS EKS with kubectl.
rem Run from the repository root with scripts\deploy-image.bat

set APP_NAME=powerjob-br55-con-1721
set NAMESPACE=powerjob-br55-con-1721
set SECRET_NAME=!APP_NAME!-secrets
set BACKUP_FILE=%TEMP%\pj_deployment.orig
set MANIFEST_SAVED=0

echo === Deploy !APP_NAME! to AWS EKS ===

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR the AWS CLI is not installed or not in PATH
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR kubectl is not installed or not in PATH
  exit /b 1
)
where powershell >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR PowerShell is required to fill the manifest placeholders
  exit /b 1
)

for %%F in (namespace deployment service ingress) do (
  if not exist "kubernetes\%%F.yaml" (
    echo ERROR kubernetes\%%F.yaml not found. Run this script from the repository root.
    exit /b 1
  )
)

rem ---------------------------------------------------------------- cluster details
set /p AWS_REGION="Enter the AWS region (for example us-east-1) "
set /p CLUSTER_NAME="Enter the EKS cluster name "
set /p IMAGE_URI="Enter the image URI (registry/repository and tag, as printed by build-push.bat) "
if "!AWS_REGION!"=="" (
  echo ERROR the AWS region, the cluster name and the image URI are required
  exit /b 1
)
if "!CLUSTER_NAME!"=="" (
  echo ERROR the AWS region, the cluster name and the image URI are required
  exit /b 1
)
if "!IMAGE_URI!"=="" (
  echo ERROR the AWS region, the cluster name and the image URI are required
  exit /b 1
)

rem ---------------------------------------------------------------- application settings
set /p DB_URL="Enter value for DB_URL (JDBC URL of the external MySQL, required) (or press Enter to skip) "
set /p DB_USERNAME="Enter value for DB_USERNAME (or press Enter to skip) "
set /p SPRING_PROFILES_ACTIVE="Enter value for SPRING_PROFILES_ACTIVE (or press Enter to skip) "
set /p OMS_MONGODB_ENABLE="Enter value for OMS_MONGODB_ENABLE (or press Enter to skip) "
if "!DB_URL!"=="" (
  echo ERROR DB_URL is required. The server cannot start without its database.
  exit /b 1
)
if "!DB_USERNAME!"=="" set DB_USERNAME=root
if "!SPRING_PROFILES_ACTIVE!"=="" set SPRING_PROFILES_ACTIVE=product
if "!OMS_MONGODB_ENABLE!"=="" set OMS_MONGODB_ENABLE=false

rem ---------------------------------------------------------------- credentials (not echoed)
call :readsecret DB_PASSWORD "Enter value for DB_PASSWORD"
call :readsecret ADMIN_PASSWORD "Enter value for ADMIN_PASSWORD (empty generates a random one)"
call :readsecret OMS_AUTH_SECURITY_JWT_SECRET "Enter value for OMS_AUTH_SECURITY_JWT_SECRET (random, 32 or more characters, same on every replica)"
call :readsecret STORAGE_DB_PASSWORD "Enter value for STORAGE_DB_PASSWORD (or press Enter to skip)"
call :readsecret MAIL_PASSWORD "Enter value for MAIL_PASSWORD (or press Enter to skip)"
call :readsecret DING_APP_KEY "Enter value for DING_APP_KEY (or press Enter to skip)"
call :readsecret DING_APP_SECRET "Enter value for DING_APP_SECRET (or press Enter to skip)"
if "!DB_PASSWORD!"=="" (
  echo ERROR DB_PASSWORD and OMS_AUTH_SECURITY_JWT_SECRET are required
  exit /b 1
)
if "!OMS_AUTH_SECURITY_JWT_SECRET!"=="" (
  echo ERROR DB_PASSWORD and OMS_AUTH_SECURITY_JWT_SECRET are required
  exit /b 1
)

rem ---------------------------------------------------------------- kubectl for the cluster
echo Configuring kubectl for the cluster !CLUSTER_NAME! in !AWS_REGION!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo ERROR aws eks update-kubeconfig failed. Check the cluster name, the region and your IAM permissions.
  exit /b 1
)
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR kubectl cannot reach the cluster
  exit /b 1
)

rem ---------------------------------------------------------------- namespace
echo Applying kubernetes\namespace.yaml...
kubectl apply -f kubernetes\namespace.yaml
if !ERRORLEVEL! neq 0 (
  echo ERROR could not apply the namespace
  exit /b 1
)

rem ---------------------------------------------------------------- secret (before the deployment)
echo Creating the secret !SECRET_NAME!...
kubectl create secret generic !SECRET_NAME! -n !NAMESPACE! --from-literal=DB_PASSWORD="!DB_PASSWORD!" --from-literal=ADMIN_PASSWORD="!ADMIN_PASSWORD!" --from-literal=OMS_AUTH_SECURITY_JWT_SECRET="!OMS_AUTH_SECURITY_JWT_SECRET!" --from-literal=STORAGE_DB_PASSWORD="!STORAGE_DB_PASSWORD!" --from-literal=MAIL_PASSWORD="!MAIL_PASSWORD!" --from-literal=DING_APP_KEY="!DING_APP_KEY!" --from-literal=DING_APP_SECRET="!DING_APP_SECRET!" --dry-run=client -o yaml | kubectl apply -f -
if !ERRORLEVEL! neq 0 (
  echo ERROR could not create the secret
  exit /b 1
)

rem ---------------------------------------------------------------- placeholders (the template is restored afterwards)
copy /y kubernetes\deployment.yaml "!BACKUP_FILE!" >nul
set MANIFEST_SAVED=1

echo Filling the placeholders of kubernetes\deployment.yaml...
call :fill IMAGE_URI
call :fill NAMESPACE
call :fill DB_URL
call :fill DB_USERNAME
call :fill SPRING_PROFILES_ACTIVE
call :fill OMS_MONGODB_ENABLE

findstr /c:"{{" kubernetes\deployment.yaml >nul 2>&1
if !ERRORLEVEL! equ 0 (
  echo ERROR unresolved placeholders remain in kubernetes\deployment.yaml
  call :restore
  exit /b 1
)

rem ---------------------------------------------------------------- apply
echo Applying kubernetes\deployment.yaml...
kubectl apply -f kubernetes\deployment.yaml
if !ERRORLEVEL! neq 0 (
  echo ERROR could not apply kubernetes\deployment.yaml
  call :restore
  exit /b 1
)
call :restore

echo Applying kubernetes\service.yaml...
kubectl apply -f kubernetes\service.yaml
if !ERRORLEVEL! neq 0 (
  echo ERROR could not apply kubernetes\service.yaml
  echo Rollback with kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo Applying kubernetes\ingress.yaml...
kubectl apply -f kubernetes\ingress.yaml
if !ERRORLEVEL! neq 0 (
  echo ERROR could not apply kubernetes\ingress.yaml
  echo Rollback with kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo Waiting for the rollout. The server needs about a minute to start.
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=600s
if !ERRORLEVEL! neq 0 (
  echo ERROR the rollout did not complete
  echo Inspect with kubectl describe pods -n !NAMESPACE! and kubectl logs deployment/!APP_NAME! -n !NAMESPACE!
  echo Rollback with kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo.
kubectl get "pods,svc,ingress" -n !NAMESPACE!

set INGRESS_HOST=
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o "jsonpath={.status.loadBalancer.ingress[0].hostname}" > "%TEMP%\pj_ingress.txt" 2>nul
set /p INGRESS_HOST=<"%TEMP%\pj_ingress.txt"
del "%TEMP%\pj_ingress.txt" >nul 2>&1

echo.
if not "!INGRESS_HOST!"=="" (
  echo Application URL is http://!INGRESS_HOST! and the ingress rule matches the host !APP_NAME!.example.com. Send that Host header or point your DNS name at this address.
) else (
  echo The load balancer address is not ready yet. Check again with kubectl get ingress -n !NAMESPACE!
)

echo.
echo Deployment finished. If something goes wrong
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
echo   kubectl rollout history deployment/!APP_NAME! -n !NAMESPACE!
endlocal
exit /b 0

:readsecret
rem Reads a value without echoing it. Arguments are the variable name and the prompt.
set "RS_NAME=%~1"
set "RS_PROMPT=%~2"
powershell -NoProfile -Command "$s = Read-Host -Prompt $env:RS_PROMPT -AsSecureString; $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); $p = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b); Set-Content -Path ($env:TEMP + '\pj_secret.txt') -Value $p -NoNewline"
set "!RS_NAME!="
set /p !RS_NAME!=<"%TEMP%\pj_secret.txt"
del "%TEMP%\pj_secret.txt" >nul 2>&1
exit /b 0

:fill
rem Replaces the placeholder of the variable named in the argument by its value, escaped for a YAML double-quoted string.
set "FILL_NAME=%~1"
powershell -NoProfile -Command "$v = [Environment]::GetEnvironmentVariable($env:FILL_NAME); $bs = [string][char]92; $dq = [string][char]34; $v = $v.Replace($bs, $bs + $bs).Replace($dq, $bs + $dq); $f = 'kubernetes\deployment.yaml'; $t = [IO.File]::ReadAllText($f); $t = $t.Replace('{{' + $env:FILL_NAME + '}}', $v); [IO.File]::WriteAllText($f, $t)"
exit /b 0

:restore
if "!MANIFEST_SAVED!"=="1" (
  copy /y "!BACKUP_FILE!" kubernetes\deployment.yaml >nul
  del "!BACKUP_FILE!" >nul 2>&1
  set MANIFEST_SAVED=0
)
exit /b 0
