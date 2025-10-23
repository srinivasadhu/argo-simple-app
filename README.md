



EKS Cluster Management with Argo CD and CloudWatch Observability
 Walkthrough on how we manage our Kubernetes workloads on Amazon EKS using Argo CD and CloudWatch Observability. 
From how developers push code in GitHub, to how those changes are automatically deployed to our cluster, monitored in CloudWatch, and alerted through Slack and Teams.
1. Understanding Amazon EKS
Let’s start from the foundation — Amazon EKS, or Elastic Kubernetes Service. EKS is Amazon’s managed Kubernetes service. It allows us to deploy, scale, and manage containerized applications without worrying about maintaining the Kubernetes control plane or master nodes. So instead of manually setting up Kubernetes components, EKS handles that for us. We just focus on defining our workloads, and EKS takes care of scheduling, load balancing, and scaling.
In simple terms — think of EKS as a container manager that runs our applications in pods on worker nodes. It’s like having an intelligent operator who makes sure our applications are always running, always healthy, and can scale up or down depending on traffic.
2. Introducing Argo CD and the GitOps Flow
Now that we understand what EKS does, let’s talk about how Argo CD fits into the picture. Argo CD is our GitOps engine — which means it automates deployments by continuously syncing the cluster with what’s defined in Git.
Here’s how the flow works:
 - Our developers make changes to Kubernetes manifests (like Deployment, Service, or ConfigMap files) in a GitHub repository.
 - Argo CD continuously monitors that repository for changes.
 - When a new commit is detected, Argo CD automatically syncs those changes to the EKS cluster.
 - This ensures that the live environment always matches what’s stored in Git.
In short — Git is our source of truth. If something changes in Git, Argo CD applies that change in EKS. This approach eliminates manual deployments, reduces errors, and gives full traceability of who changed what and when.
3. Developer Workflow — From Code to Cluster
Let’s imagine a typical developer workflow. Suppose a developer wants to update the version of an application running on EKS. They open a pull request in GitHub, update the image tag in the deployment manifest, and merge it into the main branch.
The moment this happens, Argo CD detects the new commit. It compares the current Git version with what’s deployed in EKS. If it finds a difference, it marks the application as ‘OutOfSync’ and begins the synchronization process.
In just a few seconds, the new image version is rolled out to EKS. The pods are updated, health checks are performed, and if everything looks good, the application is marked as ‘Synced’. No manual kubectl commands, no waiting — it’s fully automated.
What’s even better is that this same process can be automated further using GitHub Actions. In our setup, we have two clusters — one created manually (Test1), and another (Test2) provisioned automatically using GitHub Actions. This ensures that even our infrastructure follows Infrastructure-as-Code practices.
4. CloudWatch Observability — Seeing Everything in One Place
Once our workloads are running on EKS, the next big question is — how do we monitor them? That’s where Amazon CloudWatch comes in.
CloudWatch is like the heartbeat monitor for our entire system. It collects logs, metrics, and events from EKS, allowing us to visualize performance, troubleshoot issues, and set up alerts.
In our environment, we’ve implemented a **cross-account observability setup** — which means we have two accounts:
 - **Source Account:** where our EKS clusters and workloads actually run.
 - **Monitor Account:** where all CloudWatch metrics and dashboards are centralized.
This setup allows multiple teams to view metrics without needing access to production accounts. In the monitor account, we can see dashboards showing CPU usage, memory consumption, pod restarts, and even latency trends across namespaces.
A sample CloudWatch query might look like this:
 ```bash
 SEARCH('{AWS/EKS, ClusterName} MetricName="CPUUtilization"', 'Average', 300)
 ```
5. Alerts — Slack and Microsoft Teams Integration
Now, let’s talk about alerts. We all know that visibility is important, but timely alerts make all the difference. That’s why we integrated Argo CD Notifications with both Slack and Microsoft Teams.
Here’s how it works — whenever there’s an important event, like:
 - A new deployment triggered by a Git commit
 - A failed sync or drift detected in the cluster
 - An application becoming unhealthy
 Argo CD sends a real-time alert to our Slack or Teams channel.
For Slack, we use a simple configuration in Argo CD’s notifications ConfigMap with a token. For Teams, we use a webhook URL generated from the Teams connector. Both platforms show clear, color-coded messages indicating whether a deployment succeeded or failed, making it easy for developers and operations teams to react quickly.
6. Best Practices and Governance
Now that we’ve seen how the system works, let’s look at some best practices that keep it secure and efficient.
1. **Git is the single source of truth** — never apply changes manually in the cluster.
 2. **Use Argo CD’s auto-sync with self-heal** — this ensures the cluster always stays in the desired state.
 3. **Leverage RBAC (Role-Based Access Control)** — restrict who can sync or delete applications.
 4. **Rotate webhook and Slack/Teams tokens** regularly.
 5. **Enable CloudTrail auditing** — so every action is traceable.
 6. **Centralize observability** using cross-account dashboards for multi-team access.
These practices ensure not just automation but also accountability and compliance — which are critical in enterprise environments.
7. Benefits and Team Impact
By bringing all of this together — EKS, Argo CD, CloudWatch, and Slack/Teams — we’ve built a system that’s both powerful and transparent.
Here’s what this setup delivers:
 - **Automation:** Every change flows automatically from Git to EKS.
 - **Visibility:** CloudWatch dashboards and real-time alerts keep everyone informed.
 - **Governance:** RBAC and audit trails enforce control and compliance.
 - **Scalability:** Cross-account observability supports multiple clusters and environments.
 - **Collaboration:** Slack and Teams bridge the gap between developers and operations.
In essence, this setup transforms the way teams manage Kubernetes environments — making deployments faster, troubleshooting easier, and communication more effective.
8. Closing Summary
To wrap up, Amazon EKS provides the managed Kubernetes foundation. Argo CD automates deployments through GitOps. CloudWatch gives us observability across multiple accounts, while Slack and Teams keep our teams informed in real time. Together, they form a complete ecosystem — one that enhances automation, visibility, and collaboration.
  I hope this  gave you a clear understanding of how we’ve built a fully automated, observant, and collaborative Kubernetes management workflow using AWS services and modern DevOps tools.







# argo-simple-app
create to test argo cd sync

kubectl apply -f argocd-notifications-cm.yaml
kubectl -n argocd get pods | grep notifications


apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    webhook: $slack-url

  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase == 'Succeeded'
      send: [slack]

  trigger.on-sync-failed: |
    - when: app.status.operationState.phase == 'Error'
      send: [slack]

  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [slack]

  template.slack: |
    message: |
      *{{.app.metadata.name}}* → *{{.app.status.operationState.phase}}*
      Sync={{.app.status.sync.status}} | Health={{.app.status.health.status}}
      Triggered by {{.context.user}} at {{.context.time}}

----------

More triggers

  trigger.on-created: |
    - when: app.status.operationState.phase == 'Running'
      send: [slack]

  trigger.on-deleted: |
    - when: app.status.operationState.phase == 'Deleted'
      send: [slack]
====================================================

data:
  context: |
    argocdUrl: http://localhost:8080
  service.slack: |
    token: $slack-token

  # Template when update starts
  template.app-update-started: |
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name}}",
          "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
          "color": "#0DADEA",
          "fields": [
            {"title": "Update Status","value": "In Progress","short": true},
            {"title": "Started At","value": "{{.app.status.operationState.startedAt}}","short": true}
          ]
        }]

  # Template when update succeeds
  template.app-update-succeeded: |
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name}}",
          "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
          "color": "#18be52",
          "fields": [
            {"title": "Sync Status","value": "{{.app.status.sync.status}}","short": true},
            {"title": "Finished At","value": "{{.app.status.operationState.finishedAt}}","short": true}
          ]
        }]

  # Template when update fails
  template.app-update-failed: |
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name}}",
          "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
          "color": "#E96D76",
          "fields": [
            {"title": "Sync Status","value": "Failed","short": true},
            {"title": "Error","value": "{{.app.status.operationState.message}}","short": true},
            {"title": "Finished At","value": "{{.app.status.operationState.finishedAt}}","short": true}
          ]
        }]

  # Triggers
  trigger.on-update-started: |
    - description: Application update started
      send: [app-update-started]
      when: app.status.operationState.phase in ['Running', 'InProgress']

  trigger.on-update-succeeded: |
    - description: Application update succeeded
      send: [app-update-succeeded]
      when: app.status.operationState.phase == 'Succeeded' and app.status.health.status == 'Healthy'

  trigger.on-update-failed: |
    - description: Application update failed
      send: [app-update-failed]
      when: app.status.operationState.phase in ['Failed', 'Error', 'Unknown']


kubectl -n argocd patch cm argocd-notifications-cm --type merge -p \
'{"data":{"subscriptions":"- triggers: [on-sync-succeeded, on-sync-failed, on-health-degraded]\n  recipients:\n  - slack:#argocd-alerts\n"}}'


kubectl -n argocd annotate application hello-nginx \
  'notifications.argoproj.io/subscribe.on-sync-succeeded.slack:#argocd-alerts=' --overwrite
kubectl -n argocd annotate application hello-nginx \
  'notifications.argoproj.io/subscribe.on-sync-failed.slack:#argocd-alerts=' --overwrite
kubectl -n argocd annotate application hello-nginx \
  'notifications.argoproj.io/subscribe.on-health-degraded.slack:#argocd-alerts=' --overwrite
  
kubectl -n argocd rollout restart deployment argocd-notifications-controller
kubectl -n argocd get pods | grep notifications

argocd app sync hello-nginx --grpc-web
