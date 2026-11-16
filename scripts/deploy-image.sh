#!/bin/bash
# Deploy the pushed PowerJob server image to AWS EKS with kubectl.
# Run from the repository root:  ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="powerjob-br55-con-1721"
NAMESPACE="powerjob-br55-con-1721"
SECRET_NAME="${APP_NAME}-secrets"

echo "=== Deploy $APP_NAME to AWS EKS ==="

for tool in aws kubectl sed; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool is not installed or not in PATH."
    exit 1
  fi
done

for f in namespace deployment service ingress; do
  if [ ! -f "kubernetes/$f.yaml" ]; then
    echo "ERROR: kubernetes/$f.yaml not found. Run this script from the repository root."
    exit 1
  fi
done

# ---------------------------------------------------------------- cluster details
read -r -p "Enter the AWS region (for example us-east-1): " AWS_REGION
read -r -p "Enter the EKS cluster name: " CLUSTER_NAME
read -r -p "Enter the image URI (registry/repository:tag, as printed by build-push.sh): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: the AWS region, the cluster name and the image URI are required."
  exit 1
fi

# ---------------------------------------------------------------- application settings
read -r -p "Enter value for DB_URL (JDBC URL of the external MySQL, required) (or press Enter to skip): " DB_URL
read -r -p "Enter value for DB_USERNAME (or press Enter to skip): " DB_USERNAME
read -r -p "Enter value for SPRING_PROFILES_ACTIVE (or press Enter to skip): " SPRING_PROFILES_ACTIVE
read -r -p "Enter value for OMS_MONGODB_ENABLE (or press Enter to skip): " OMS_MONGODB_ENABLE
if [ -z "$DB_URL" ]; then
  echo "ERROR: DB_URL is required: the server cannot start without its database."
  exit 1
fi
DB_USERNAME=${DB_USERNAME:-root}
SPRING_PROFILES_ACTIVE=${SPRING_PROFILES_ACTIVE:-product}
OMS_MONGODB_ENABLE=${OMS_MONGODB_ENABLE:-false}

# ---------------------------------------------------------------- credentials (not echoed)
read -r -s -p "Enter value for DB_PASSWORD: " DB_PASSWORD; echo ""
read -r -s -p "Enter value for ADMIN_PASSWORD (initial admin password; empty generates a random one): " ADMIN_PASSWORD; echo ""
read -r -s -p "Enter value for OMS_AUTH_SECURITY_JWT_SECRET (random, 32+ characters, same on every replica): " OMS_AUTH_SECURITY_JWT_SECRET; echo ""
read -r -s -p "Enter value for STORAGE_DB_PASSWORD (or press Enter to skip): " STORAGE_DB_PASSWORD; echo ""
read -r -s -p "Enter value for MAIL_PASSWORD (or press Enter to skip): " MAIL_PASSWORD; echo ""
read -r -s -p "Enter value for DING_APP_KEY (or press Enter to skip): " DING_APP_KEY; echo ""
read -r -s -p "Enter value for DING_APP_SECRET (or press Enter to skip): " DING_APP_SECRET; echo ""
if [ -z "$DB_PASSWORD" ] || [ -z "$OMS_AUTH_SECURITY_JWT_SECRET" ]; then
  echo "ERROR: DB_PASSWORD and OMS_AUTH_SECURITY_JWT_SECRET are required."
  exit 1
fi

# ---------------------------------------------------------------- kubectl for the cluster
echo "Configuring kubectl for the cluster $CLUSTER_NAME in $AWS_REGION..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME || {
  echo "ERROR: aws eks update-kubeconfig failed. Check the cluster name, the region and your IAM permissions."
  exit 1
}
kubectl cluster-info || exit 1

# ---------------------------------------------------------------- keep the manifest template intact
WORK_DIR=$(mktemp -d)
cp kubernetes/deployment.yaml "$WORK_DIR/deployment.yaml.orig"
restore_manifest() {
  cp "$WORK_DIR/deployment.yaml.orig" kubernetes/deployment.yaml
  rm -f kubernetes/deployment.yaml.bak
  rm -rf "$WORK_DIR"
}
trap restore_manifest EXIT

# value escaped for a YAML double-quoted string, then for the replacement part of sed
escape_value() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | sed -e 's/[\\|&]/\\&/g'
}

# ---------------------------------------------------------------- namespace
echo "Applying kubernetes/namespace.yaml..."
kubectl apply -f kubernetes/namespace.yaml || {
  echo "ERROR: could not apply the namespace."
  exit 1
}

# ---------------------------------------------------------------- secret (before the deployment)
echo "Creating the secret $SECRET_NAME..."
kubectl create secret generic $SECRET_NAME -n $NAMESPACE \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  --from-literal=OMS_AUTH_SECURITY_JWT_SECRET="$OMS_AUTH_SECURITY_JWT_SECRET" \
  --from-literal=STORAGE_DB_PASSWORD="$STORAGE_DB_PASSWORD" \
  --from-literal=MAIL_PASSWORD="$MAIL_PASSWORD" \
  --from-literal=DING_APP_KEY="$DING_APP_KEY" \
  --from-literal=DING_APP_SECRET="$DING_APP_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f - || {
  echo "ERROR: could not create the secret."
  exit 1
}

# ---------------------------------------------------------------- placeholders
echo "Filling the placeholders of kubernetes/deployment.yaml..."
sed -i.bak 's|{{IMAGE_URI}}|'"$(escape_value "$IMAGE_URI")"'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{NAMESPACE}}|'"$(escape_value "$NAMESPACE")"'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{DB_URL}}|'"$(escape_value "$DB_URL")"'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{DB_USERNAME}}|'"$(escape_value "$DB_USERNAME")"'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{SPRING_PROFILES_ACTIVE}}|'"$(escape_value "$SPRING_PROFILES_ACTIVE")"'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{OMS_MONGODB_ENABLE}}|'"$(escape_value "$OMS_MONGODB_ENABLE")"'|g' kubernetes/deployment.yaml
rm -f kubernetes/deployment.yaml.bak

if grep -q '{{' kubernetes/deployment.yaml; then
  echo "ERROR: unresolved placeholders remain in kubernetes/deployment.yaml:"
  grep -n '{{' kubernetes/deployment.yaml
  exit 1
fi

# ---------------------------------------------------------------- apply
for f in deployment service ingress; do
  echo "Applying kubernetes/$f.yaml..."
  kubectl apply -f kubernetes/$f.yaml || {
    echo "ERROR: could not apply kubernetes/$f.yaml."
    echo "Rollback: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
    exit 1
  }
done

echo "Waiting for the rollout (the server needs about a minute to start)..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=600s; then
  echo "ERROR: the rollout did not complete."
  echo "Inspect:  kubectl describe pods -n $NAMESPACE   and   kubectl logs deployment/$APP_NAME -n $NAMESPACE"
  echo "Rollback: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

echo ""
kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
echo ""
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST (the ingress rule matches the host ${APP_NAME}.example.com; send that Host header or point your DNS name at this address)"
else
  echo "The load balancer address is not ready yet. Check again with: kubectl get ingress -n $NAMESPACE"
fi

echo ""
echo "Deployment finished. If something goes wrong:"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
echo "  kubectl rollout history deployment/$APP_NAME -n $NAMESPACE"
