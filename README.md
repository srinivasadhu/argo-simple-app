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

APP=hello-nginx
kubectl -n argocd annotate application $APP \
  'notifications.argoproj.io/subscribe.on-sync-succeeded.slack:#argocd-alerts=' --overwrite
kubectl -n argocd annotate application $APP \
  'notifications.argoproj.io/subscribe.on-sync-failed.slack:#argocd-alerts=' --overwrite
kubectl -n argocd annotate application $APP \
  'notifications.argoproj.io/subscribe.on-health-degraded.slack:#argocd-alerts=' --overwrite
  
kubectl -n argocd rollout restart deployment argocd-notifications-controller
kubectl -n argocd get pods | grep notifications

argocd app sync hello-nginx --grpc-web
