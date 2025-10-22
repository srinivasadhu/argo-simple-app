# EKS Cluster Management Workflow using Argo CD - Guide

## 1. Overview
This guide explains how to manage Kubernetes workloads on **Amazon EKS** using **Argo CD** in a GitOps model.  
It includes end-to-end steps for setup, RBAC enforcement, drift detection, Slack integration, audit traceability, and a demo script suitable for team presentations.

---

## 2. Architecture Diagram
The architecture integrates **GitHub**, **Argo CD**, **Amazon EKS**, **AWS IAM**, **CloudWatch**, **CloudTrail**, and **Slack** to deliver a full GitOps workflow with security, observability, and automation.

  

<img width="975" height="650" alt="image" src="https://github.com/user-attachments/assets/61887b12-baf7-4549-988f-2a74f79c3fbe" />

**Figure 1:** AWS-style architecture showing developer commits → Argo CD GitOps sync → EKS deployment → Slack alerts → CloudWatch/CloudTrail observability.

---

## 3. End-to-End GitOps Workflow
The **GitOps model** automates application deployment by using Git as the single source of truth.

**Flow:**
1. Developer commits code or manifest changes to GitHub.  
2. Argo CD continuously monitors the Git repository.  
3. On detecting changes, Argo CD syncs the manifests to the EKS cluster.  
4. Kubernetes resources are created or updated.  
5. Argo CD updates app status (`Synced` / `OutOfSync`).  
6. Slack notifications trigger on sync, drift, or health events.

---

## 4. RBAC Deep Dive
Argo CD uses **Role-Based Access Control (RBAC)** to enforce access boundaries.  
Define roles in `argocd-rbac-cm` to separate **Admin** and **Viewer** access.

```yaml
p, role:admin, applications, *, *, allow
p, role:viewer, applications, get, *, allow

g, admin-user, role:admin
g, viewer-user, role:viewer
```

**Admin Capabilities**
- Full control: sync, rollback, delete  
- Manage repos and projects  

**Viewer Capabilities**
- Read-only access to applications and statuses  

---

## 5. Sync Lifecycle
Argo CD maintains continuous reconciliation between Git and the cluster.

**Sync Types:**
- **Manual:** triggered via UI or CLI  
  ```bash
  argocd app sync nginx-demo
  ```
- **Automated:** `syncPolicy.automated` keeps Git and cluster aligned automatically  

**Common CLI Commands:**
```bash
argocd app sync <app>
argocd app diff <app>
argocd app history <app>
```

---

## 6. Drift & Untracked Changes
Drift occurs when live cluster state differs from Git.  
Untracked (orphaned) resources appear when manual changes are made via `kubectl`.

**Detection:**
- Argo CD marks app as **OutOfSync**.  
- UI → “Resources” tab highlights orphaned resources.  
- CLI:
  ```bash
  argocd app diff <app>
  argocd app get <app> --output json | jq '.status.resources[].status'
  ```

**Finding Who Made the Change:**
- Use **Kubernetes audit logs** or **AWS CloudTrail** to track `Update`, `Patch`, or `Delete` API calls.  
- Identify the IAM user or service account responsible.

**Remediation:**
- Trigger a manual or automated sync to restore Git-defined state.  
- Optionally enable `selfHeal: true` for auto-correction.

---

## 7. Slack Notification Lifecycle
Argo CD integrates with **Slack** using `argocd-notifications` for real-time alerts.

### Setup
```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/stable/manifests/install.yaml
```

### Configuration
```yaml
service.slack: |
  token: xoxb-<slack-token>
  default: notifications

trigger.on-sync-status-change: |
  - description: Sync status changed
    send: [slack]

template.slack: |
  text: |
    *Argo CD Alert:*
    App: {{.app.metadata.name}}
    Status: {{.app.status.sync.status}}
    Health: {{.app.status.health.status}}
    Commit: {{.app.status.operationState.syncResult.revision}}
    Time: {{.time}}
```

**Events:**
- `on-sync-status-change`  
- `on-health-degraded`  
- `on-deployed`  

---

## 8. Operational Best Practices
- Enable **auto-sync with prune and self-heal** for production.  
- Use **CloudWatch dashboards** for EKS monitoring.  
- Maintain audit trails with **CloudTrail**.  
- Keep Git as **the source of truth** for manifests.  
- Enforce namespace isolation and periodic **RBAC reviews**.  
- Secure webhook and Slack token management using **Secrets Manager**.

---

## 9. Troubleshooting & Recovery
**Common Issues**
| Issue | Resolution |
|-------|-------------|
| App OutOfSync | `argocd app sync <app>` |
| Drift not detected | Check `argocd-repo-server` logs |
| Slack alert not sent | Verify webhook & CM config |
| RBAC access denied | Check `argocd-rbac-cm` mappings |

**Recovery Strategies**
- Revert to a previous Git commit.  
- Enable **automated rollback** on failure.  
- Configure Slack alerts for OutOfSync and health degradation.  

---

## 10. 1-Hour Demo Narrative (Speaking Script)
**0–10 min:**  
- Introduce GitOps, Argo CD, and EKS.  
- Explain architecture and flow.

**10–25 min:**  
- Show Argo CD dashboard, login, app creation.  
- Demonstrate sync and app states.  

**25–40 min:**  
- Simulate RBAC restriction (Viewer denied sync).  
- Perform manual `kubectl delete` to simulate drift.  
- Show Argo CD detecting drift and self-heal.

**40–50 min:**  
- Trigger sync → observe Slack alerts.  
- Display OutOfSync → Synced transitions in Slack.

**50–60 min:**  
- Summarize GitOps advantages.  
- Emphasize audit visibility and automation benefits.  
- Q&A.

---

## 11. Benefits Recap
| Feature | Benefit |
|----------|----------|
| **GitOps Automation** | Continuous delivery through Git commits |
| **RBAC Security** | Granular role enforcement |
| **Drift Detection** | Self-healing, audit-ready |
| **Slack Alerts** | Real-time deployment visibility |
| **CloudTrail + CloudWatch** | Full traceability & monitoring |

---

## 12. References
- [Argo CD Official Docs](https://argo-cd.readthedocs.io)  
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks)  
- [Argo CD Notifications](https://argocd-notifications.readthedocs.io)

---

**Author:** *Srinivas Dhulipalla*  
**Project:** *Norfolk Southern EKS GitOps Implementation (AWS ProServe)*  
**Version:** 1.0 | **Last Updated:** October 2025  
