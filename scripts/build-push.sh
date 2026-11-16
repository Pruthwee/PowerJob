#!/bin/bash
# Build the PowerJob server image and push it to AWS ECR or Docker Hub.
# Run from the repository root:  ./scripts/build-push.sh
set -e
set -o pipefail

PROJECT_NAME="powerjob-br55-con-1721"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== Build and push: $IMAGE_NAME ==="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed or not in PATH."
  exit 1
fi

if [ ! -f "Dockerfile" ]; then
  echo "ERROR: Dockerfile not found. Run this script from the repository root (./scripts/build-push.sh)."
  exit 1
fi

echo ""
echo "Select the registry:"
echo "  1. AWS ECR (Elastic Container Registry)"
echo "  2. Docker Hub"
read -r -p "Enter 1 or 2: " REGISTRY_CHOICE

case "$REGISTRY_CHOICE" in
  1)
    REGISTRY_TYPE="ecr"
    if ! command -v aws >/dev/null 2>&1; then
      echo "ERROR: the AWS CLI is not installed or not in PATH."
      exit 1
    fi
    read -r -p "Enter the AWS region (for example us-east-1): " AWS_REGION
    if [ -z "$AWS_REGION" ]; then
      echo "ERROR: the AWS region is required."
      exit 1
    fi
    read -r -p "Enter the AWS account ID (press Enter to look it up with the AWS CLI): " AWS_ACCOUNT_ID
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      echo "Looking up the AWS account ID..."
      AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || {
        echo "ERROR: could not determine the AWS account ID. Check your AWS credentials."
        exit 1
      }
    fi
    read -r -p "Enter the ECR repository name (press Enter for $IMAGE_NAME): " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    ECR_REPO=$(echo "$ECR_REPO" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    REPO_PATH="$ECR_REPO"
    ;;
  2)
    REGISTRY_TYPE="dockerhub"
    read -r -p "Enter your Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter your Docker Hub password or access token: " DOCKER_PASSWORD
    echo ""
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
      echo "ERROR: the Docker Hub username and password are required."
      exit 1
    fi
    read -r -p "Enter the Docker Hub repository name (press Enter for $IMAGE_NAME): " DOCKER_REPO
    DOCKER_REPO=${DOCKER_REPO:-$IMAGE_NAME}
    DOCKER_REPO=$(echo "$DOCKER_REPO" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
    DOCKER_USERNAME_LC=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    REGISTRY_URL="docker.io"
    REPO_PATH="${DOCKER_USERNAME_LC}/${DOCKER_REPO}"
    ;;
  *)
    echo "ERROR: invalid choice. Enter 1 or 2."
    exit 1
    ;;
esac

read -r -p "Enter the image tag (press Enter for latest): " IMAGE_TAG
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

FULL_IMAGE_NAME="${REGISTRY_URL}/${REPO_PATH}:${IMAGE_TAG}"

echo ""
echo "Image to build and push: $FULL_IMAGE_NAME"
echo ""

echo "[1/3] Building the Docker image (this compiles every module; it can take several minutes)..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .
echo "Build completed."

echo "[2/3] Logging in to the registry..."
if [ "$REGISTRY_TYPE" = "ecr" ]; then
  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY_URL
  echo "Checking the ECR repository $ECR_REPO..."
  aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION >/dev/null 2>&1 || aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION
else
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
fi
echo "Login succeeded."

echo "[3/3] Pushing the image..."
docker push "$FULL_IMAGE_NAME"

echo ""
echo "Done. Image pushed: $FULL_IMAGE_NAME"
echo "Next step: ./scripts/deploy-image.sh (use the image URI above)."
