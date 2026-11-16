# Deployment guide - powerjob-br55-con-1721 (PowerJob server) on AWS EKS

This guide covers the PowerJob server (`powerjob-server/powerjob-server-starter`, Spring Boot 2.7, Java 8) packaged as one container and deployed to **AWS EKS** with `kubectl`.
The container holds the application only. MySQL, MongoDB (optional) and SMTP are external services reached through environment variables.

## 1. Prerequisites and system requirements

| Tool | Use |
|------|-----|
| Docker 20.10+ | build and push the image (not needed on the cluster) |
| AWS CLI v2 | ECR login, `aws eks update-kubeconfig` |
| kubectl (within one minor version of the cluster) | apply manifests |
| eksctl | create the cluster (optional) |
| Java 8 + Maven 3.8+ | only for building outside Docker |

IAM permissions of the deploying user/role: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`, `ecr:CreateRepository`, `ecr:DescribeRepositories`, `eks:DescribeCluster`, plus an EKS access entry or `aws-auth` mapping that lets the user manage the namespace.

System requirements per pod: 0.25 CPU / 512 MiB requested, 0.5 CPU / 1 GiB limit (see `kubernetes/deployment.yaml`). An external MySQL 5.7/8 database with the PowerJob schema is required for the `product` profile.
The AWS Load Balancer Controller must be installed in the cluster for `kubernetes/ingress.yaml`.

## 2. Local setup with Docker Compose

`docker-compose.yml` runs exactly one service, the application. Credentials are taken from the shell that runs compose; nothing is written in the file.

```bash
export DB_URL='jdbc:mysql://<db-host>:3306/powerjob-product?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC'
export DB_USERNAME='<user>'
export DB_PASSWORD='<password>'
export ADMIN_PASSWORD='<initial admin password>'
export OMS_AUTH_SECURITY_JWT_SECRET='<random string, 32+ characters>'
docker compose up --build
```

The UI/API is then on http://localhost:7700 and the health endpoint on http://localhost:7700/actuator/health. Data and logs are kept in `./powerjob-data/powerjob-server` (mounted on `/home/powerjob/powerjob`).
`docker compose` was not run while this guide was written (no Docker in the build environment): run it once before relying on it.

## 3. Build and push

Both scripts run from the repository root. They ask for the registry (1 = AWS ECR, 2 = Docker Hub), then its details, then `IMAGE_TAG` (empty means `latest`).

```bash
./scripts/build-push.sh        # Linux / macOS
scripts\build-push.bat         # Windows
```

For ECR they run `aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY_URL`, create the repository when it is missing and push `<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>`.
The image name is `powerjob-br55-con-1721`. The build context is always the repository root (`docker build -f Dockerfile ... .`).

## 4. Deployment on AWS EKS

### 4.1 Cluster setup and kubectl configuration

```bash
eksctl create cluster --name powerjob-cluster --region eu-west-1 --nodegroup-name workers --node-type t3.large --nodes 2
aws eks update-kubeconfig --region eu-west-1 --name powerjob-cluster
kubectl cluster-info
```

Install the AWS Load Balancer Controller (Helm chart `eks/aws-load-balancer-controller`) so the Ingress creates an ALB. The cluster nodes must reach the MySQL database (same VPC or peering, security group rule on port 3306).

### 4.2 Deploy

```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```

The script asks for the AWS region, the cluster name, the image URI (registry, repository and tag), the non-secret settings (`SPRING_PROFILES_ACTIVE`, `DB_URL`, `DB_USERNAME`, `OMS_MONGODB_ENABLE`) and, without echo, the credentials. It then:

1. runs `aws eks update-kubeconfig` and `kubectl cluster-info`;
2. applies `kubernetes/namespace.yaml`;
3. creates the Secret `powerjob-br55-con-1721-secrets` (`DB_PASSWORD`, `ADMIN_PASSWORD`, `OMS_AUTH_SECURITY_JWT_SECRET`, `STORAGE_DB_PASSWORD`, `MAIL_PASSWORD`, `DING_APP_KEY`, `DING_APP_SECRET`) with `kubectl create secret generic ... --dry-run=client -o yaml | kubectl apply -f -`;
4. replaces the `"{{...}}"` placeholders of `deployment.yaml` (a copy of the original is restored when the script ends);
5. applies `deployment.yaml`, `service.yaml`, `ingress.yaml` in that order, waits with `kubectl rollout status deployment/powerjob-br55-con-1721 -n powerjob-br55-con-1721` and prints `kubectl get pods,svc,ingress -n powerjob-br55-con-1721` and the application URL.

If a step fails the script stops and prints the rollback command: `kubectl rollout undo deployment/powerjob-br55-con-1721 -n powerjob-br55-con-1721`.
The scripts were checked for syntax only; they were not run here (no AWS account, cluster or kubectl).

### 4.3 The manifests

| File | Content |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `powerjob-br55-con-1721`, label `name: powerjob-br55-con-1721` |
| `kubernetes/deployment.yaml` | 2 replicas, container `powerjob-br55-con-1721`, image `"{{IMAGE_URI}}"`, ports 7700 (HTTP), 10086 (AKKA), 10010 (HTTP transporter), 10077 (MU), env from placeholders and from the Secret, requests 250m/512Mi, limits 500m/1Gi, liveness/readiness probes on `/actuator/health/liveness` and `/actuator/health/readiness` (port 7700), non-root user 10001, `emptyDir` for `/home/powerjob/powerjob` |
| `kubernetes/service.yaml` | ClusterIP `powerjob-br55-con-1721-service`, port 80 to 7700 |
| `kubernetes/ingress.yaml` | `powerjob-br55-con-1721-ingress`, ALB (`kubernetes.io/ingress.class: alb`, `alb.ingress.kubernetes.io/scheme: internet-facing`), host `powerjob-br55-con-1721.example.com`, path `/` to the service on port 80 |

Edit the host in `ingress.yaml` before the first deployment. Workers outside the cluster must reach the server on 10086/10010/10077: expose those ports (for example with an NLB Service) if you run workers outside Kubernetes.

## 5. Configuration management and environment variables

| Variable | Kind | Meaning |
|----------|------|---------|
| `SPRING_PROFILES_ACTIVE` | plain | `daily`, `pre` or `product` (image default `product`) |
| `SPRING_DATASOURCE_CORE_JDBC_URL` | plain | JDBC URL of the external MySQL (set from `DB_URL`) |
| `SPRING_DATASOURCE_CORE_USERNAME` | plain | database user (from `DB_USERNAME`) |
| `OMS_MONGODB_ENABLE` | plain | `true` to use MongoDB for logs/storage |
| `DB_PASSWORD` | Secret | database password (`spring.datasource.core.password=${DB_PASSWORD:}`) |
| `ADMIN_PASSWORD` | Secret | initial admin password |
| `OMS_AUTH_SECURITY_JWT_SECRET` | Secret | JWT signing secret, 32+ characters, same on every replica |
| `STORAGE_DB_PASSWORD`, `MAIL_PASSWORD`, `DING_APP_KEY`, `DING_APP_SECRET` | Secret | optional integrations |
| `POWERJOB_RND_PORT_START` / `POWERJOB_RND_PORT_END` | plain | random port range used when a transporter port is not fixed (default 30000-65535) |
| `POWERJOB_LOCALHOST_VALUE` / `POWERJOB_ANY_HOST_VALUE` | plain | loopback / wildcard address (defaults 127.0.0.1 / 0.0.0.0) |
| `AKKA_BIND_HOSTNAME` | plain | AKKA bind address (default wildcard) |
| `POWERJOB_AVAILABLE_PROCESSORS` | plain | pin the CPU count used for pool sizing |
| `POWERJOB_TIMING_POOL_MAX_MULTIPLIER`, `POWERJOB_BG_POOL_CORE_MULTIPLIER`, `POWERJOB_BG_POOL_MAX_MULTIPLIER`, `POWERJOB_SCHEDULER_POOL_MULTIPLIER`, `POWERJOB_SCHEDULER_POOL_MIN`, `POWERJOB_TIMEWHEEL_THREAD_MULTIPLIER`, `POWERJOB_TIMEWHEEL_QUEUE_SIZE`, `POWERJOB_TIMEWHEEL_POOL_MAX_MULTIPLIER`, `POWERJOB_TIMEWHEEL_PENDING_QUEUE_SIZE`, `POWERJOB_TIMEWHEEL_CANCEL_QUEUE_SIZE`, `POWERJOB_ALARM_POOL_MULTIPLIER`, `POWERJOB_LIGHT_TASK_THREAD_MULTIPLIER`, `POWERJOB_LOG_QUEUE_SIZE`, `POWERJOB_STATUS_RETRY_QUEUE_SIZE`, `POWERJOB_PROCESSOR_POOL_MAX_SIZE` | plain | thread pool and queue tuning; every default equals the value that was hard-coded before |

Any other Spring property can be set through the environment (`SPRING_...` / `OMS_...`, relaxed binding) or a ConfigMap.

## 6. Security considerations and best practices

- No credential is stored in the image, the manifests or the repository: the tracked `application*.properties` now read `${DB_PASSWORD:}`, `${ADMIN_PASSWORD:}` etc. from the environment. Rotate any password that was committed in the past.
- Credentials live in the Kubernetes Secret `powerjob-br55-con-1721-secrets`; consider AWS Secrets Manager with the Secrets Store CSI driver and IRSA.
- The container runs as non-root (uid 10001); the runtime image has no package manager step and no extra tools.
- Restrict the ALB with security groups/WAF, use an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`, HTTPS listener).
- Keep the database in private subnets; allow only the node security group.
- Use a private ECR repository with image scanning enabled.
- Scripts (shell/python) executed by PowerJob processors run inside the pod with the pod's privileges: keep the pod security context restricted.

## 7. Java notes

- Runtime image: `eclipse-temurin:8-jdk`, built from `maven:3.8.6-openjdk-8-slim`. Entry point: `sh -c "exec java $JAVA_OPTS -jar /app/app.jar"` so that `java` receives SIGTERM (graceful shutdown, `terminationGracePeriodSeconds: 45`).
- JVM settings: `JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 ..."`. With a 1 GiB limit, `-Xmx512m` leaves room for metaspace, threads and Akka/Netty buffers. If you raise the memory limit, raise `-Xmx` (or drop it and rely on `MaxRAMPercentage`); keep heap below about 75% of the limit. Java 8u191+ is container aware.
- `TZ=UTC`, `LANG=C.UTF-8`, `-Dfile.encoding=UTF-8`.
- Spring profiles: `daily`, `pre`, `product` (`application-<profile>.properties`). The base `application.properties` defaults to `daily`; the image and the manifests set `product`.
- Health: the application already had Spring Boot Actuator (`spring-boot-starter-actuator` in `powerjob-server/pom.xml`), so `/actuator/health` was kept and nothing was added. The manifest sets `MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true`, which exposes `/actuator/health/liveness` and `/actuator/health/readiness`; the probes and the ALB health check use them on port 7700. The server keeps running and answers from start-up. First start (schema validation, Akka start) can take 60-90 s: the probes allow for it.
- The Dockerfile has no `HEALTHCHECK`; the platform probes the actuator endpoint.

## 8. Troubleshooting

### Pod failures
- `kubectl get pods -n powerjob-br55-con-1721`, `kubectl describe pod <pod> -n powerjob-br55-con-1721`, `kubectl logs <pod> -n powerjob-br55-con-1721`.
- `ImagePullBackOff`: wrong `IMAGE_URI`, or the node role lacks `AmazonEC2ContainerRegistryReadOnly`.
- `CrashLoopBackOff` with database errors: check `DB_URL`, the credentials in the Secret and the security group of the database. With the `product` profile the schema must be reachable at start-up.
- `OOMKilled`: raise the memory limit and `-Xmx` together.
- Readiness never true: check `kubectl exec <pod> -- ...` is not required; read the log for the actuator health details (a failing DB health indicator keeps the pod unready).

### Service issues
- `kubectl get endpoints powerjob-br55-con-1721-service -n powerjob-br55-con-1721` must list pod IPs; if empty the selector `app: powerjob-br55-con-1721` or the readiness probe is the cause.
- `kubectl port-forward svc/powerjob-br55-con-1721-service 8080:80 -n powerjob-br55-con-1721` to test inside the cluster.

### Ingress problems
- `kubectl describe ingress powerjob-br55-con-1721-ingress -n powerjob-br55-con-1721`; no ADDRESS means the AWS Load Balancer Controller is missing or lacks IAM rights (`kubectl logs -n kube-system deployment/aws-load-balancer-controller`).
- ALB target group unhealthy: the health check path is `/actuator/health/readiness`; confirm the probes are enabled.
- Subnets need the tags `kubernetes.io/role/elb=1` (public).

## 9. Scaling and management

- Manual: `kubectl scale deployment/powerjob-br55-con-1721 --replicas=3 -n powerjob-br55-con-1721`.
- HPA (needs metrics-server): `kubectl autoscale deployment powerjob-br55-con-1721 --cpu-percent=70 --min=2 --max=6 -n powerjob-br55-con-1721`. PowerJob servers share the database; all replicas must use the same `OMS_AUTH_SECURITY_JWT_SECRET`.
- Rolling update: change the image with `kubectl set image deployment/powerjob-br55-con-1721 powerjob-br55-con-1721=<new image> -n powerjob-br55-con-1721` (strategy RollingUpdate, maxUnavailable 0), watch with `kubectl rollout status`.
- Rollback: `kubectl rollout history deployment/powerjob-br55-con-1721 -n ...` then `kubectl rollout undo deployment/powerjob-br55-con-1721 -n ...` (add `--to-revision=N`).
- Data in the `emptyDir` volume (local logs, embedded H2 work files) is lost when a pod is replaced; use the external database/MongoDB for data that must survive, or mount an EFS volume if local files must persist.
- Cluster nodes: `eksctl scale nodegroup --cluster powerjob-cluster --name workers --nodes 3`.
- Cleanup: `kubectl delete namespace powerjob-br55-con-1721`.
