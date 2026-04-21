# GitHub Actions Secrets

Set these at: https://github.com/Kunal2703/8byteOps/settings/secrets/actions

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access key for the `github-actions-ci` IAM user |
| `AWS_SECRET_ACCESS_KEY` | Secret key for the same user |
| `GH_PAT` | Personal Access Token with `repo` and `workflow` scopes |

---

## Creating the PAT

Go to https://github.com/settings/tokens and create a token with:
- `repo` — full repository access
- `workflow` — update GitHub Actions workflows

---

## IAM User Permissions

The `github-actions-ci` IAM user needs:
- `AmazonEC2ContainerRegistryFullAccess`
- `AmazonEKSClusterPolicy`
- Inline policy for `eks:AccessKubernetesApi` and `eks:DescribeCluster`

The user also needs to be in the EKS `aws-auth` ConfigMap with `system:masters` group. The `setup.sh` script handles this automatically.

---

## Production Environment

The `production` GitHub Environment adds a manual approval gate before the deploy job runs.

1. Go to https://github.com/Kunal2703/8byteOps/settings/environments
2. Create environment named `production`
3. Under Protection rules, enable Required reviewers
4. Add yourself as a reviewer

---

## Quick Setup via CLI

```bash
gh auth login
gh secret set AWS_ACCESS_KEY_ID     --repo Kunal2703/8byteOps
gh secret set AWS_SECRET_ACCESS_KEY --repo Kunal2703/8byteOps
gh secret set GH_PAT                --repo Kunal2703/8byteOps
```
