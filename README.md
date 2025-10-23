EKS Cluster Management Workflow using Argo CD — Full Demo Guide
1. Overview
This comprehensive guide demonstrates how to manage Kubernetes workloads on Amazon EKS using Argo CD. The document covers architecture, GitOps flow, RBAC enforcement, drift detection, Slack notifications, and audit traceability. It is structured for a one-hour technical demo with detailed speaking notes for delivery.
2. Architecture Diagram
The architecture demonstrates integration between GitHub, Argo CD, Amazon EKS, AWS IAM, CloudWatch, CloudTrail, and Slack. The flow represents developer-driven GitOps synchronization, policy enforcement, and alert notifications.
<img width="975" height="650" alt="image" src="https://github.com/user-attachments/assets/61887b12-baf7-4549-988f-2a74f79c3fbe" />

 
Figure 1: AWS-style architecture for Argo CD and EKS integration with Slack.
3. End-to-End GitOps Workflow
The GitOps model automates application deployment by linking Git repositories as the single source of truth. Every change to infrastructure or code triggers an automated synchronization process between GitHub and the EKS cluster via Argo CD.
Step-by-Step Flow:
1. Developer commits code or Kubernetes manifest changes to GitHub.
2. Argo CD continuously monitors the Git repository.
3. Upon detecting changes, Argo CD syncs the manifests to the EKS cluster.
4. Kubernetes resources are created or updated as defined in Git.
5. Argo CD updates application status (Synced/OutOfSync) in its dashboard.
6. Slack notifications are triggered based on configured events such as sync success, drift, or failure.
4. RBAC Deep Dive
Argo CD implements Role-Based Access Control (RBAC) via the argocd-rbac-cm ConfigMap. This enforces access segregation between administrative and viewer roles, ensuring governance and compliance.
Admin Role Capabilities:
- Full control over applications and clusters.
- Can sync, rollback, and delete applications.
- Manages repository and project configurations.

Viewer Role Capabilities:
- Read-only access to applications and statuses.
- Cannot modify, sync, or delete resources.
Example RBAC Policy (policy.csv):
p, role:admin, applications, *, *, allow
p, role:viewer, applications, get, *, allow
g, admin-user, role:admin
g, viewer-user, role:viewer
5. Sync Lifecycle
Argo CD's reconciliation loop ensures the live cluster state matches the desired Git state.
Sync Types:
- Manual Sync: Triggered by users via UI or CLI.
- Automated Sync: Continuously keeps Git and cluster in sync.
During synchronization, Argo CD compares manifests from Git to those in the cluster and applies updates or rollbacks accordingly.
Common CLI Commands:
- argocd app sync <app>
- argocd app diff <app>
- argocd app history <app>
6. Drift & Untracked Changes
Configuration drift occurs when the actual cluster state deviates from the Git repository. Untracked changes are resources manually applied via kubectl that are not defined in Git.
Drift Detection Process:
1. Argo CD detects differences between Git and the cluster using periodic reconciliation.
2. The application state changes to OutOfSync.
3. Slack notifications alert the team to review the drift.
4. Admins can trigger auto-heal or manual sync to restore consistency.
Finding Untracked Changes:
- Use Argo CD UI → Resources tab to identify orphaned resources.
- Run 'argocd app diff <app>' to view discrepancies.
- To trace who made the change, check Kubernetes audit logs or AWS CloudTrail for Update or Patch events.
7. Slack Notification Lifecycle
Argo CD integrates with Slack through the argocd-notifications controller, allowing real-time alerts for deployment, drift, and health events.
Configuration Steps:
1. Deploy Argo CD Notifications extension.
2. Add Slack service configuration in argocd-notifications-cm.
3. Define triggers for on-sync-status-change, on-health-degraded, etc.
4. Include a Slack webhook token for message delivery.
Sample Notification Template:
template.slack: |
  text: |
    *Argo CD Alert*:
    Application: {{.app.metadata.name}}
    Status: {{.app.status.sync.status}}
    Health: {{.app.status.health.status}}
    Commit: {{.app.status.operationState.syncResult.revision}}
    Time: {{.time}}
8. Operational Best Practices
- Enable auto-sync with prune and self-heal for production environments.
- Integrate CloudWatch dashboards to monitor EKS metrics.
- Use CloudTrail to maintain an audit trail of manual changes.
- Keep Git as the single source of truth.
- Implement network policies and namespace isolation for security.
- Perform periodic RBAC reviews.
9. Troubleshooting & Recovery Scenarios
Common Issues:
- Application OutOfSync: Run 'argocd app sync'.
- Drift not detected: Check argocd-repo-server logs.
- Notification failure: Verify Slack webhook and ConfigMap settings.
- Access Denied: Review RBAC roles and user bindings.
Recovery Strategies:
- Use Git revert to roll back changes.
- Enable automated rollback on failure.
- Configure alerts for drift and sync failure to ensure proactive response.


