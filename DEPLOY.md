# Deployment Workflow

You now have two environments:
1.  **Staging**: `habitslogger.web.app` (Target: `staging`)
2.  **Production**: `daycoach.web.app` (Target: `app`)

## 1. Test in Staging
When you have made changes and want to verify them in a live-like environment without affecting users:

```bash
flutter build web
firebase deploy --only hosting:staging
```
Visit [https://habitslogger.web.app](https://habitslogger.web.app) to verify.

## 2. Promote to Production
When you are happy with the changes in Staging:

```bash
firebase deploy --only hosting:app
```
Visit [https://daycoach.web.app](https://daycoach.web.app) to confirm.

## Summary
- **Staging**: `firebase deploy --only hosting:staging`
- **Production**: `firebase deploy --only hosting:app`
