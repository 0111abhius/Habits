# Deployment

Two Firebase Hosting targets live in the `habitslogger` project (they share one
Firestore database and one Auth user pool):

| Target    | URL                                                   | Deployed by                                   |
|-----------|-------------------------------------------------------|-----------------------------------------------|
| `staging` | [https://habitslogger.web.app](https://habitslogger.web.app) | every push to `main` (or `master`), or manual run          |
| `app`     | [https://daycoach.web.app](https://daycoach.web.app)         | manual run of the "Deploy web" workflow        |

## One-time setup (GitHub Actions)

Add these repository secrets under **Settings → Secrets and variables → Actions**:

- `FIREBASE_SERVICE_ACCOUNT_HABITSLOGGER` – JSON key for a service account with
  the *Firebase Hosting Admin* role on `habitslogger`. The quickest way to
  create it is `firebase init hosting:github` from a machine where you are
  logged in with `firebase login`; it creates the service account and uploads
  the secret for you (delete the extra workflow files it generates).
- `GEMINI_API_KEY` – written to `assets/env` at build time so AI features work.

## Deploy to staging

- Merge / push to `main`, **or**
- GitHub → *Actions* → *Deploy web* → *Run workflow* → target `staging`,
  picking any branch (useful to try a feature branch before merging).

Pull requests automatically get a 7-day preview URL posted as a comment.

## Promote to production

GitHub → *Actions* → *Deploy web* → *Run workflow* → target `app`.

## Manual deploy from your machine

```bash
echo "GEMINI_API_KEY=..." > assets/env   # git-ignored
flutter build web --release
firebase deploy --only hosting:staging   # or hosting:app
```
