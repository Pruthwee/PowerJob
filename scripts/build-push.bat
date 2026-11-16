@echo off & setlocal enabledelayedexpansion
rem Build the PowerJob server image and push it to AWS ECR or Docker Hub.
rem Run from the repository root with scripts\build-push.bat

set PROJECT_NAME=powerjob-br55-con-1721
set "SAN_RE=[^a-z0-9]+"
call :sanitize "!PROJECT_NAME!"
set IMAGE_NAME=!SAN_OUT!

echo === Build and push for !IMAGE_NAME! ===

where docker >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR docker is not installed or not in PATH
  exit /b 1
)

if not exist "Dockerfile" (
  echo ERROR Dockerfile not found. Run this script from the repository root with scripts\build-push.bat
  exit /b 1
)

echo.
echo Select the registry
echo   1. AWS ECR (Elastic Container Registry)
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter 1 or 2 "

if "!REGISTRY_CHOICE!"=="1" (
  set REGISTRY_TYPE=ecr
  where aws >nul 2>&1
  if !ERRORLEVEL! neq 0 (
    echo ERROR the AWS CLI is not installed or not in PATH
    exit /b 1
  )
  set /p AWS_REGION="Enter the AWS region (for example us-east-1) "
  if "!AWS_REGION!"=="" (
    echo ERROR the AWS region is required
    exit /b 1
  )
  set /p AWS_ACCOUNT_ID="Enter the AWS account ID (press Enter to look it up with the AWS CLI) "
  if "!AWS_ACCOUNT_ID!"=="" (
    echo Looking up the AWS account ID...
    aws sts get-caller-identity --query Account --output text > "%TEMP%\pj_account.txt"
    if !ERRORLEVEL! neq 0 (
      echo ERROR could not determine the AWS account ID. Check your AWS credentials.
      exit /b 1
    )
    set /p AWS_ACCOUNT_ID=<"%TEMP%\pj_account.txt"
    del "%TEMP%\pj_account.txt" >nul 2>&1
  )
  set /p ECR_REPO="Enter the ECR repository name (press Enter for !IMAGE_NAME!) "
  if "!ECR_REPO!"=="" set ECR_REPO=!IMAGE_NAME!
  set "SAN_RE=[^a-z0-9]+"
  call :sanitize "!ECR_REPO!"
  set ECR_REPO=!SAN_OUT!
  set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
  set REPO_PATH=!ECR_REPO!
) else if "!REGISTRY_CHOICE!"=="2" (
  set REGISTRY_TYPE=dockerhub
  set /p DOCKER_USERNAME="Enter your Docker Hub username "
  set /p DOCKER_PASSWORD="Enter your Docker Hub password or access token "
  if "!DOCKER_USERNAME!"=="" (
    echo ERROR the Docker Hub username and password are required
    exit /b 1
  )
  if "!DOCKER_PASSWORD!"=="" (
    echo ERROR the Docker Hub username and password are required
    exit /b 1
  )
  set /p DOCKER_REPO="Enter the Docker Hub repository name (press Enter for !IMAGE_NAME!) "
  if "!DOCKER_REPO!"=="" set DOCKER_REPO=!IMAGE_NAME!
  set "SAN_RE=[^a-z0-9]+"
  call :sanitize "!DOCKER_REPO!"
  set DOCKER_REPO=!SAN_OUT!
  call :sanitize "!DOCKER_USERNAME!"
  set DOCKER_USERNAME_LC=!SAN_OUT!
  set REGISTRY_URL=docker.io
  set REPO_PATH=!DOCKER_USERNAME_LC!/!DOCKER_REPO!
) else (
  echo ERROR invalid choice. Enter 1 or 2.
  exit /b 1
)

set /p IMAGE_TAG="Enter the image tag (press Enter for latest) "
set "SAN_RE=[^a-z0-9._-]+"
call :sanitize "!IMAGE_TAG!"
set IMAGE_TAG=!SAN_OUT!
if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

set FULL_IMAGE_NAME=!REGISTRY_URL!/!REPO_PATH!:!IMAGE_TAG!

echo.
echo Image to build and push !FULL_IMAGE_NAME!
echo.

echo [1/3] Building the Docker image. This compiles every module and can take several minutes.
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)
echo Build completed.

echo [2/3] Logging in to the registry...
if "!REGISTRY_TYPE!"=="ecr" (
  aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
  if !ERRORLEVEL! neq 0 (
    echo ECR login failed
    exit /b 1
  )
  echo Checking the ECR repository !ECR_REPO!...
  aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
  if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
      echo Could not create the ECR repository
      exit /b 1
    )
  )
) else (
  echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
  if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed
    exit /b 1
  )
)
echo Login succeeded.

echo [3/3] Pushing the image...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo.
echo Done. Image pushed !FULL_IMAGE_NAME!
echo Next step scripts\deploy-image.bat (use the image URI above).
endlocal
exit /b 0

:sanitize
rem Lower-cases the value, turns each run of characters outside SAN_RE into one hyphen and trims hyphens at both ends.
set "SAN_IN=%~1"
powershell -NoProfile -Command "$s = $env:SAN_IN.ToLower() -replace $env:SAN_RE, '-'; $s = $s.Trim('-'); Set-Content -Path ($env:TEMP + '\pj_san.txt') -Value $s -NoNewline"
set "SAN_OUT="
set /p SAN_OUT=<"%TEMP%\pj_san.txt"
del "%TEMP%\pj_san.txt" >nul 2>&1
exit /b 0
