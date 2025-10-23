# EKS Cluster Management with Argo CD and CloudWatch Observability

Walkthrough and operational README describing how we manage Kubernetes workloads on Amazon EKS using Argo CD (GitOps) and CloudWatch observability, with alerting into Slack and Microsoft Teams.
<img width="864" height="583" alt="image" src="https://github.com/user-attachments/assets/d8188c04-ce1a-49c0-bcb2-8723b4404df9" />



This document covers:
- High level architecture
- Developer workflow (Git → Argo CD → EKS)
- GitHub Actions for infra & app pipelines
- Argo CD / Notifications examples (Slack & Teams)
- CloudWatch cross-account observability patterns
- Best practices, security and governance
- Troubleshooting & contacts

---

## 1. Overview

We run workloads on Amazon EKS. Argo CD is our GitOps engine that continuously syncs the cluster to manifests stored in Git. CloudWatch centralizes metrics, logs, and dashboards into a dedicated Monitor Account so teams can observe production without needing full access to production accounts. Argo CD Notifications deliver deployment and health alerts to Slack and Microsoft Teams.

Benefits:
- Single source of truth (Git)
- Automated, auditable deployments
- Centralized observability and alerts
- RBAC and auditability for governance
- Faster collaboration between devs and SREs

---

## 2. High-level architecture

1. Developers push Kubernetes manifests or image tag changes to GitHub (repo per app, or repo-per-environment).
2. Argo CD watches Git repos and auto-syncs changes to EKS clusters.
3. CloudWatch agents / FluentD / Container insights send metrics and logs to the Source Account.
4. CloudWatch cross-account aggregation or log forwarding moves observability data to the Monitor Account.
5. Alarms & CloudWatch EventBridge rules trigger notifications to Slack / Teams using Argo CD Notifications or Lambda/CloudWatch Alarm actions.
6. GitHub Actions used for infra provisioning (IaC) and optionally for CI processes.

(Optionally: GitHub Actions provisions cluster resources using EKS Blueprints, eksctl, or Terraform; uses OIDC to get short-lived AWS credentials.)

---

## 3. Developer workflow (Git → Cluster)

Typical flow:
1. Developer updates deployment manifest (e.g., image tag) and opens a PR.
2. CI (GitHub Actions) runs tests and policy checks (optional).
3. PR merged into `main` (or environment branch).
4. Argo CD detects new commit, marks application OutOfSync and performs sync (auto-sync/self-heal if enabled).
5. Pods roll out; readiness & liveness probes validate new pods.
6. On success/failure, Argo CD updates status and sends notifications.

Advantages:
- No manual kubectl apply in production
- Full audit trail of what changed and who changed it
- Rollbacks via Git or Argo CD UI

---

## 4. Quick examples

Argo CD Application (K8s manifest) example:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example-app
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: example
  project: default
  source:
    repoURL: https://github.com/your-org/your-app-configs
    targetRevision: main
    path: apps/example
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Argo CD Notifications - Slack (ConfigMap + Secret approach):
```yaml
# secret containing slack token (kubernetes secret)
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: xoxb-xxxxxxxxxxxxxxxx

---
# config map to define template and trigger
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  templates.yaml: |
    templates:
      app-sync-success:
        message: |
          Application {{.app.metadata.name}} has been synced successfully.
      app-sync-failed:
        message: |
          Application {{.app.metadata.name}} failed to sync: {{.app.status.sync.revision}}
  triggers.yaml: |
    triggers:
      - name: on-sync-succeeded
        condition: app.status.operationState.phase == 'Succeeded'
        template: app-sync-success
        recipients:
        - slack:general

  services.yaml: |
    services:
      slack:
        token: $slack-token
        channel: "general"
```

Argo CD Notifications - Microsoft Teams (use incoming webhook URL stored in secret):
```yaml
# Secret with teams webhook URL
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  teams-webhook-url: https://outlook.office.com/webhook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# In config map services.yaml
services:
  teams:
    webhook: $teams-webhook-url
    title: "ArgoCD Notification"
```

Note: Use Kubernetes Secrets to store tokens & webhook URLs. Rotate regularly.

---

## 5. CloudWatch Observability (Cross-account)

Patterns to centralize observability:

- Metrics:
  - Use CloudWatch cross-account observability or CloudWatch Resource Sharing to share CloudWatch dashboards and cross-account access for metrics visualization in the Monitor Account.
  - Grant read-only metric access to the Monitor Account via IAM resource policies where supported.

- Logs:
  - Forward logs from EKS (Fluent Bit/Fluentd) to a central account via:
    - Kinesis Firehose (cross-account destinations) or
    - CloudWatch Logs subscription filters that forward to a central Kinesis/Lambda in the Monitor Account.
  - Alternatively, configure log aggregation to an S3 bucket in the Monitor Account (if required) for long-term storage.

- Dashboards:
  - Create centralized dashboards in Monitor Account that reference metrics/logs from source accounts (or import metric streams into the monitor account).

Sample CloudWatch Metrics query:
```bash
SEARCH('{AWS/EKS,ClusterName} MetricName="CPUUtilization"', 'Average', 300)
```

Security & access:
- Use cross-account IAM roles with least privilege for metric/log access.
- Enable CloudTrail in all accounts and aggregate trails to a central S3 bucket or to CloudWatch Logs in the Monitor Account for auditing.

---

## 6. GitHub Actions — Example tasks

- Provision EKS cluster (Test2) via Terraform or eksctl:
  - Use OIDC trust to allow GitHub Actions to assume a role with limited permissions.
- Deploy manifests/helm to Git repo (Argo CD will apply).
- Run image build and push to ECR, then update manifests (commit new image tag).

Example (high level):
```yaml
name: ci
on: [push]
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: us-east-1
      - name: Build and push image
        run: |
          docker build -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:$GITHUB_SHA .
          docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:$GITHUB_SHA
      - name: Update manifest and push
        run: |
          # update k8s manifest image tag and push to repo that Argo CD monitors
```

---

## 7. Alerts & Incident Flow

- CloudWatch Alarms fire for important thresholds (high CPU, high error rate, large pod restarts).
- Alarms publish to SNS topics or EventBridge rules.
- Targets for SNS/EventBridge:
  - Lambda (to format & forward to Teams)
  - Direct webhook to Slack (via SNS HTTP subscription or a forwarding Lambda)
  - Argo CD notifications for sync/health events go directly from Argo CD to Slack/Teams

Example alerting flow:
1. PodCrashLoopDetected alarm → SNS topic → Lambda formats payload → POST to Teams webhook.
2. Argo CD failed sync → Argo CD Notifications pushes to Slack channel with link to Argo CD UI and commit info.

---

## 8. Security, Governance & Best Practices

- Git is the single source of truth — never apply manual changes directly to production clusters.
- Use Argo CD auto-sync + self-heal for drift remediation.
- Use RBAC for Argo CD UI / API. Limit sync and delete permissions to authorized roles.
- Store secrets in a secure secret manager (AWS Secrets Manager, HashiCorp Vault, or sealed-secrets / ExternalSecrets), not in Git.
- Rotate webhook and chat tokens regularly and store them as Kubernetes Secrets.
- Enable CloudTrail and aggregate trails for auditing. Use AWS Config rules where applicable.
- Use OIDC for GitHub Actions to avoid long-lived credentials.
- Add policy-as-code checks (e.g., OPA/Gatekeeper, Conftest) as part of CI to prevent bad manifests from being merged.
- Implement resource quotas and limit ranges in clusters to avoid noisy neighbors.
- Maintain separate Git repos or branches for environments (dev/test/prod) and restrict merging to protected branches.

---

## 9. Troubleshooting

- Argo CD UI:
  - Check Application events and operation logs for sync failures.
  - Use `kubectl -n argocd get pods` to verify Argo CD components.
- EKS Pod issues:
  - `kubectl -n <ns> describe pod <pod>` to view events.
  - `kubectl -n <ns> logs <pod> -c <container>` for container logs.
- CloudWatch:
  - Check metric streams and log delivery status.
  - Validate subscription filters and Lambda forwarding logs in Monitor Account.
- Notification failures:
  - Ensure webhooks/tokens are valid and reachable from Argo CD or from the Lambda used to send messages.

---

## 10. Useful links & references

- Argo CD: https://argo-cd.readthedocs.io/
- AWS EKS: https://docs.aws.amazon.com/eks/
- CloudWatch: https://docs.aws.amazon.com/cloudwatch/
- GitHub OIDC for Actions: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- Example patterns: centralized logging via Kinesis or CloudWatch Logs subscription filters; use IAM cross-account roles for metric/log read access.

---

 
 
