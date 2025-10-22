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
