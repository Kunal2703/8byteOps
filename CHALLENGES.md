# Challenges & Resolutions

Issues encountered during the implementation, what caused them, and how they were fixed.

---

## Terraform

### EKS version and AMI type
Initial config used EKS 1.29 with `AL2_x86_64`. Amazon Linux 2 is end-of-life for EKS 1.33+, and 1.29 support had ended.

Updated to EKS 1.33 with `AL2023_x86_64_STANDARD`. Had to update both the cluster version variable and the node group AMI type.

---

### RDS password rejected
Password `DevOps@Demo2024!` was rejected by RDS:
```
The parameter MasterUserPassword is not a valid password.
Only printable ASCII characters besides '/', '@', '"', ' ' may be used.
```

Changed to alphanumeric only. RDS has stricter rules than most services.

---

### RDS backup retention on free tier
```
FreeTierRestrictionError: The specified backup retention period exceeds
the maximum available to free tier customers.
```

Set `backup_retention_period = 0`. For a paid account this should be 7+.

---

### Bastion AMI disk size
EC2 creation failed because the AL2023 AMI requires a minimum 30 GB root volume. The config had 20 GB. Updated `volume_size` to 30.

---

### CloudWatch alarm percentile statistic
Terraform plan failed:
```
expected statistic to be one of ["SampleCount" "Average" "Sum" "Minimum" "Maximum"], got p95
```

Percentile stats use `extended_statistic`, not `statistic`. Changed `statistic = "p95"` to `extended_statistic = "p95"`.

---

### EKS log group conflict
EKS automatically creates `/aws/eks/<cluster>/cluster` when control plane logging is enabled. Terraform tried to create it again and failed.

Added `lifecycle { ignore_changes = [tags] }` to the log group resource.

---

### Secrets Manager recovery window on re-apply
After `terraform destroy`, secrets go into a 7-day recovery window. Re-applying immediately fails:
```
You can't create this secret because a secret with this name is already scheduled for deletion.
```

Set `recovery_window_in_days = 0` in the secrets module. For production this should stay at the default (30 days).

---

### LB controller IAM policy — AddTags 403
The ALB controller kept logging:
```
AccessDenied: not authorized to perform: elasticloadbalancing:AddTags
```

The IAM policy had `AddTags` with a `Null` condition requiring `elbv2.k8s.aws/cluster` and `ingress.k8s.aws/cluster` tags. Existing target groups don't have those tags, so the condition always failed.

Removed the conditions and merged all `AddTags` statements into one unconditional rule covering all ELB resources.

---

### Security group circular dependency
The `security_groups` module needed the EKS cluster primary SG ID (to allow ALB → pods on port 3000 and EKS cluster SG → RDS on 5432), but the EKS module needed the `eks_nodes_sg_id` from `security_groups`.

Resolved by passing `module.eks.cluster_primary_sg_id` into the `security_groups` module. Terraform handles this correctly since it only needs the value at apply time, not plan time.

---

## EKS / Kubernetes

### t3.micro — too many pods
Pods stuck in `Pending`:
```
0/2 nodes are available: 2 Too many pods.
```

t3.micro has a VPC CNI limit of 4 pods per node. System pods (coredns, kube-proxy, aws-node, ebs-csi) already fill those slots. Switched to t3.small which supports 11 pods per node.

---

### EKS addon timeout
EKS addons took 20+ minutes and timed out. Root cause was the same t3.micro capacity issue — addons couldn't schedule. After switching to t3.small, addons installed in ~2 minutes.

---

### kubectl credentials error from GitHub Actions
```
error: unable to recognize "k8s/namespace.yaml": the server has asked for the client to provide credentials
```

The `github-actions-ci` IAM user wasn't in the EKS `aws-auth` ConfigMap. Added it with `system:masters` group.

---

### Bastion can't reach EKS API
`kubectl` commands from the bastion timed out even after the IAM role was correct.

The EKS API endpoint resolves to private IPs. The bastion is in a public subnet. Added security group rules to allow port 443 from the public subnet CIDRs to the EKS cluster primary SG.

---

### Ingress stuck on terraform destroy
`terraform destroy` hung on `module.alb.kubernetes_ingress_v1.app` for 10+ minutes.

The ingress had a finalizer `ingress.k8s.aws/resources` set by the ALB controller. The controller was supposed to remove it after cleaning up the ALB, but it was stuck. Force-removed the finalizer:
```bash
kubectl patch ingress devops-demo-ingress -n production \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

### Namespace stuck terminating on destroy
After the ingress was deleted, the `production` namespace was stuck terminating:
```
Some resources are remaining: targetgroupbindings.elbv2.k8s.aws has 1 resource instances
Some content in the namespace has finalizers remaining: elbv2.k8s.aws/resources
```

Force-removed the finalizer on the `targetgroupbinding`:
```bash
kubectl patch targetgroupbinding k8s-producti-devopsde-af9af4fcc7 -n production \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

## Networking

### RDS connection timeout from pods
App pods couldn't reach RDS. The RDS security group allowed traffic from `eks-nodes-sg` (our custom SG), but EKS managed node groups attach the **cluster primary SG** created by the EKS module — not the custom one.

Added an inbound rule to the RDS SG allowing port 5432 from the EKS cluster primary SG. Also updated the Terraform `security_groups` module so this is handled automatically on future applies.

---

### RDS SSL required
After fixing the network, pods still couldn't connect:
```
no pg_hba.conf entry for host "...", no encryption
```

RDS enforces SSL by default. Set `DB_SSL=true` in the deployment and migration job manifests, and updated `app/src/db.js` to pass `ssl: { rejectUnauthorized: false }` when SSL is enabled.

---

### ALB targets unhealthy — Target.Timeout
ALB health checks failed. The ALB uses IP target mode and sends traffic directly to pod IPs on port 3000. The EKS cluster primary SG had no rule allowing the ALB SG on port 3000.

Added an inbound rule: ALB SG → EKS cluster primary SG on TCP 3000. Also added this to the Terraform `security_groups` module.

---

## Application

### UI returning 404
`/health` and `/todos` worked but `/` returned 404. The `public/` folder wasn't being copied into the Docker image. Added `COPY public/ ./public/` to the Dockerfile.

---

### DB connection timeout on first connect
First connection to RDS was timing out. `app/src/db.js` had `connectionTimeoutMillis: 2000`. The SSL handshake + DNS resolution on first connect takes 3-5 seconds. Increased to 5000ms.

---

### npm dependency conflict
```
ERESOLVE unable to resolve dependency tree
peer prom-client@">= 10.x <= 13.x" from express-prometheus-middleware@1.2.0
```

`express-prometheus-middleware` only supports `prom-client` up to v13. Downgraded `prom-client` from 15.x to 13.2.0.

---

## Operations

### Terraform state lock after failed apply
Multiple failed apply attempts left stale locks in DynamoDB. Subsequent runs blocked with "acquiring state lock".

```bash
# get the lock ID
aws dynamodb scan --table-name terraform-state-lock --region us-east-1

# force unlock
terraform force-unlock <lock-id>
```

---

### Bastion user-data curl conflict
AL2023 ships `curl-minimal` by default. Adding `curl` to the dnf install list caused a conflict. Removed `curl` from the install list — `curl-minimal` is sufficient.

---

### sed delimiter in shell commands
`sed 's|:latest|:v1.0.0|g'` failed in some contexts because `|` was interpreted as a pipe. Changed to `sed "s#:latest#:${TAG}#g"` using `#` as the delimiter.

---

## Key Learnings

- EKS managed node groups use the cluster primary SG, not any custom SG you define. Always check which SG the nodes actually have before writing security group rules.
- IRSA trust policies use `sts:AssumeRoleWithWebIdentity` with an OIDC condition. The service account namespace and name must match exactly.
- IP target mode on ALB means the ALB talks directly to pod IPs. Security group rules need to allow the ALB SG to reach the node SG on the app port.
- Terraform destroy can get stuck on Kubernetes resources that have finalizers. The ALB controller sets finalizers on ingresses and target group bindings — if the controller is gone or stuck, you need to manually patch the finalizers out.
- AL2023 requires a minimum 30 GB root volume. AL2 worked with 20 GB.
