# Deploy Kapé Lumen to AWS (runbook)

**Owner:** you · **Region:** `ap-southeast-1` (Singapore) for everything · **Takes:** about 2 hours the first time
**Last tested:** _not yet; fill in the date when you've run it end to end_

```
You ─HTTPS─> Elastic IP ─> EC2 t3.small (Ubuntu 24.04, encrypted 30 GB disk)
                             ├─ caddy        :80/:443, free Let's Encrypt cert for <ip>.sslip.io
                             ├─ LibreChat    (reskinned UI)
                             ├─ MongoDB      (auth on, internal network only)
                             └─ brew-gateway ─> Gemini API
                                   ├─ café docs from S3 (versioned bucket)
                                   └─ Gemini key from SSM Parameter Store (SecureString)
        CloudWatch Logs /kape/*  ·  CloudWatch agent (memory/disk)  ·  SNS email  ·  CloudTrail
```

Every step below says what to expect. **Screenshot the things marked 📸 as you go.** They're evidence the brief asks for, and you can't recreate them later.

> **Never paste access keys, the Gemini key or any password into chat, a file in this repo, or a screenshot.**

---

## Part A — Account safety (AWS console, as root, ~30 min)

### A1. Root MFA
Console → top-right account name → **Security credentials** → **Assign MFA device** → Authenticator app. 📸 (E-12)

### A2. Budget alert (do this before anything that costs money)
Console → **Billing and Cost Management → Budgets → Create budget** → *Use a template* → **Monthly cost budget**. Set **$10**, enter your email → Create.
Add a second one at **$25**, or set alert thresholds of 50%/80%/100% on the first.
Also: **Billing preferences → Alert preferences → Receive CloudWatch billing alerts** (needed for the billing alarm in the monitoring phase).

### A3. Admin role + your own IAM user
In **IAM**:
1. **Policies → Create policy → JSON**: paste [`infra/iam/operator-user-policy.json`](../infra/iam/operator-user-policy.json), replacing `ACCOUNT_ID` with your 12-digit account ID. Name it `KapeOperatorSelfService`.
2. **Roles → Create role → AWS account → This account**, tick **Require MFA** → attach `AdministratorAccess` → name it **`KapeAdminRole`**. Set **Maximum session duration** to 1 hour.
3. **Users → Create user**: your name (e.g. `renzo`), tick **Provide user access to the console**. Attach **`ReadOnlyAccess`** and **`KapeOperatorSelfService`**. Nothing else: everyday you can look but not change; to change things you switch into the admin role with MFA.
4. Sign out of root. Sign in as the new user (use the account's sign-in URL from the IAM dashboard).
5. **Security credentials → Assign MFA device** for your user. 📸 (E-12)
6. Same page → **Create access key → Command Line Interface**. Keep the window open for step B2.

From now on, **don't use root** except for billing.

### A4. CloudTrail
Switch role first: top-right menu → **Switch role** → account ID, role `KapeAdminRole`.
**CloudTrail → Create trail** → name `kape-trail`, new S3 bucket, leave **Log file SSE-KMS encryption** off (costs extra), Management events: Read + Write → Create. 📸 (E-12 / security page)

---

## Part B — Your PC (Git Bash, ~10 min)

### B1. Install the AWS CLI (once)
```powershell
winget install -e --id Amazon.AWSCLI
```
Open a **new Git Bash** window afterwards.

### B2. Sign in the CLI as your user, with an MFA-protected admin profile
```bash
aws configure --profile kape-user
```
Paste the access key + secret from A3.6, region `ap-southeast-1`, output `json`.

Then add the admin profile (replace `ACCOUNT_ID` and `YOUR_USER` first):
```bash
cat >> ~/.aws/config <<'EOF'

[profile kape]
role_arn = arn:aws:iam::ACCOUNT_ID:role/KapeAdminRole
source_profile = kape-user
mfa_serial = arn:aws:iam::ACCOUNT_ID:mfa/YOUR_USER
region = ap-southeast-1
duration_seconds = 3600
EOF
```
Use it for the rest of this runbook:
```bash
export AWS_PROFILE=kape MSYS_NO_PATHCONV=1
```
```bash
aws sts get-caller-identity
```
✅ It asks for your MFA code and shows `assumed-role/KapeAdminRole/...`. 📸 (good E-12 evidence: you work through a role, not as an admin user)

> `MSYS_NO_PATHCONV=1` stops Git Bash turning names like `/kape/gateway` into Windows paths. If a command fails with a path like `C:/Program Files/Git/kape/...`, you forgot it.

### B3. Variables used below
Run in the project folder (`cd /c/xampp/htdocs/SAM10_Final-Project`):
```bash
export REGION=ap-southeast-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export BUCKET=kape-lumen-content-$ACCOUNT_ID
echo "$ACCOUNT_ID $BUCKET"
```

---

## Part C — Data and secrets (~15 min)

### C1. S3 bucket for café content and backups
```bash
aws s3api create-bucket --bucket $BUCKET --region $REGION --create-bucket-configuration LocationConstraint=$REGION
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
aws s3api put-bucket-tagging --bucket $BUCKET --tagging 'TagSet=[{Key=Project,Value=SAM10}]'
```
Backups expire after 14 days; old versions of content after 30 days:
```bash
aws s3api put-bucket-lifecycle-configuration --bucket $BUCKET --lifecycle-configuration '{"Rules":[{"ID":"expire-backups","Status":"Enabled","Filter":{"Prefix":"backups/"},"Expiration":{"Days":14},"NoncurrentVersionExpiration":{"NoncurrentDays":14}},{"ID":"old-content-versions","Status":"Enabled","Filter":{"Prefix":"content/"},"NoncurrentVersionExpiration":{"NoncurrentDays":30}}]}'
```
Upload the café docs:
```bash
./infra/sync-content.sh $BUCKET
```
✅ Lists 5 `.md` files. 📸 bucket **Properties** tab showing *Bucket Versioning: Enabled* (WS-C.3).

### C2. Secrets in Parameter Store
```bash
./infra/create-secrets.sh $BUCKET
```
It generates LibreChat's secrets, the MongoDB password and the gateway token (never printed), then asks for your **Gemini key** with the input hidden.
✅ A table of names, all `SecureString` except `CONTENT_BUCKET`. 📸 **Systems Manager → Parameter Store** list (names only, never click "Show decrypted value" in a screenshot) (E-13).

---

## Part D — Logs, alerts, permissions, network (~15 min)

### D1. Log groups with a retention period (not "Never expire")
```bash
for g in caddy librechat mongo gateway host; do
  aws logs create-log-group --log-group-name /kape/$g --tags Project=SAM10 2>/dev/null || true
  aws logs put-retention-policy --log-group-name /kape/$g --retention-in-days 14
done
aws logs describe-log-groups --log-group-name-prefix /kape --query 'logGroups[].[logGroupName,retentionInDays]' --output table
```

### D2. Alerts topic (email)
```bash
aws sns create-topic --name kape-alerts --tags Key=Project,Value=SAM10
aws sns subscribe --topic-arn arn:aws:sns:$REGION:$ACCOUNT_ID:kape-alerts --protocol email --notification-endpoint YOUR_EMAIL
```
✅ Click **Confirm subscription** in the email AWS sends you.

### D3. The instance's role (least privilege)
```bash
sed -e "s/ACCOUNT_ID/$ACCOUNT_ID/g" -e "s/BUCKET_NAME/$BUCKET/g" infra/iam/kape-instance-policy.json > infra/iam/kape-instance-policy.rendered.json
aws iam create-role --role-name KapeEc2Role --assume-role-policy-document file://infra/iam/ec2-trust.json --tags Key=Project,Value=SAM10
aws iam put-role-policy --role-name KapeEc2Role --policy-name KapeEc2Least --policy-document file://infra/iam/kape-instance-policy.rendered.json
aws iam attach-role-policy --role-name KapeEc2Role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name KapeEc2Profile
aws iam add-role-to-instance-profile --instance-profile-name KapeEc2Profile --role-name KapeEc2Role
```
What it may do: read `content/` and write `backups/` in **one** bucket, read **only** `/kape-lumen/*` parameters, write to `/kape/*` log groups, publish metrics, send to `kape-alerts`, and be reached by Session Manager. Nothing else.

### D4. Security group: only HTTP and HTTPS, no SSH
```bash
export VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
export SG_ID=$(aws ec2 create-security-group --group-name kape-web --description "Kape Lumen: HTTP/HTTPS only" --vpc-id $VPC_ID --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' 'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]'
aws ec2 create-tags --resources $SG_ID --tags Key=Project,Value=SAM10
echo $SG_ID
```
No port 22: you get a shell through **Session Manager** instead (console → EC2 → instance → **Connect → Session Manager**). MongoDB has no port open at all.

---

## Part E — Launch (~20 min, mostly waiting)

> The instance clones the repo from GitHub on first boot, so **push your latest commits first** (GitHub Desktop → Push origin). Otherwise it deploys old code.

### E1. Reserve the public IP first, so the HTTPS name is known before boot
```bash
export EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Project,Value=SAM10}]' --query AllocationId --output text)
export EIP=$(aws ec2 describe-addresses --allocation-ids $EIP_ALLOC --query 'Addresses[0].PublicIp' --output text)
export SITE=${EIP//./-}.sslip.io
aws ssm put-parameter --name /kape-lumen/env/SITE_ADDRESS --type String --value $SITE --overwrite
echo "Your site will be: https://$SITE"
```

### E2. Start the instance
```bash
export AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)
export INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI --instance-type t3.small \
  --iam-instance-profile Name=KapeEc2Profile \
  --security-group-ids $SG_ID \
  --user-data file://infra/bootstrap.sh \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
  --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kape-lumen},{Key=Project,Value=SAM10}]' 'ResourceType=volume,Tags=[{Key=Project,Value=SAM10}]' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOC
echo $INSTANCE_ID
```
Notes on the choices (you'll be asked):
- `HttpTokens=required`: IMDSv2 only, which blocks a common credential-theft trick. `HopLimit=2` lets the gateway container reach it.
- `Encrypted=true`: disk encrypted at rest (an S-level item).
- `--user-data`: runs [`infra/bootstrap.sh`](../infra/bootstrap.sh) on first boot.

### E3. Watch it come up (5–10 minutes)
```bash
aws logs tail /kape/host --follow
```
✅ You should see `=== bootstrap finished ...` and a `docker compose ps` table with 4 containers `Up`. (If `/kape/host` stays empty for 10 min, open **Connect → Session Manager** and run `sudo tail -f /var/log/kape-bootstrap.log`.)

### E4. Check it
```bash
curl -sI https://$SITE | head -5
```
✅ `HTTP/2 200` and no certificate warning. Open `https://$SITE` in a browser → register with an **invented** account → ask "How much is an iced Spanish latte?". 📸 the page with the URL bar visible (E-02).

Check the request reached CloudWatch:
```bash
aws logs tail /kape/gateway --since 10m | grep chat_request
```

---

## Part F — Record the baseline (do it the same day)

The brief's **baseline** is "the environment before you touched it". For us, that's stock LibreChat run the way its own `docker-compose.yml` does it. Write these down for the website's Baseline page and the security before/after table:

| Area | Stock LibreChat (before) | Kapé Lumen on AWS (after) |
|---|---|---|
| Transport | Plain HTTP on port 3080 | HTTPS via Caddy + Let's Encrypt, HTTP redirects |
| Database | MongoDB with `--noauth` | Auth on, password in SSM, no port exposed |
| App secrets | `.env.example` ships public default `CREDS_KEY`/`JWT_SECRET` | Random per deployment, SecureString in SSM |
| AI key | In `.env` on disk | In SSM, read by the gateway at runtime |
| Admin access | n/a | IAM user (read-only) + MFA-protected admin role, root unused |
| Remote shell | SSH port 22 (typical) | No SSH; Session Manager, logged |
| Logs | Container files, no retention | CloudWatch, 14-day retention |
| Extras running | RAG API, vector DB, search, admin panel | Only what we use (4 containers) |

From today, also note **daily cost** (Billing → Cost Explorer, daily, filter tag `Project=SAM10`) and the response time and error rate (from the monitoring dashboard). Equal-length before/after periods matter more than long ones.

---

## Part G — Monitoring, backups and restore

### G1. Put the new scripts on the server
The backup, restore and site-check scripts live in `infra/ops/`. Cron runs them on the server from `infra/cron/kape-lumen`. Push your commits first, then redeploy:
```bash
aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript --parameters 'commands=["/opt/kape/app/infra/deploy.sh"]' --query Command.CommandId --output text
```
Or use the console: EC2 → instance → **Connect → Session Manager** → `sudo /opt/kape/app/infra/deploy.sh`. The deploy also installs the cron jobs.

| When (PHT) | Job | Result metric | Alarm |
|---|---|---|---|
| every minute | `probe.sh`: fetch `https://<site>/health` from outside | `SiteUp` | `kape-site-down` |
| 02:00 nightly | `backup.sh`: database + uploads to `s3://…/backups/<time>/` | `BackupSuccess`, `BackupSizeBytes` | `kape-backup-missing` (and an email straight away on failure) |
| 03:30 Sundays | `restore.sh --test latest`: restore into a test database and check it | `RestoreTestSuccess` | email on failure |

### G2. Alarms and dashboard (from your PC)
```bash
./infra/monitoring/setup-monitoring.sh
```
This creates the log-based metrics, **10 alarms** (all email `kape-alerts` when they fire and again when they clear) and the `kape-lumen` dashboard. It ends with a table of alarm states. `INSUFFICIENT_DATA` is normal for the first few minutes, and `kape-backup-missing` shows `ALARM` until the first backup runs (G3).

| Alarm | Fires when | Automatic action |
|---|---|---|
| kape-site-down | 3 failed checks in a row, **or no checks at all** (instance dead) | email |
| kape-ec2-hardware-check | AWS host problem | email + **auto-recover** to new hardware |
| kape-ec2-os-check | OS stopped responding | email + **auto-reboot** |
| kape-cpu-high | CPU > 80% for 15 min | email |
| kape-memory-high | memory > 85% for 10 min | email |
| kape-disk-high | disk > 80% | email |
| kape-answers-failing | ≥ 3 failed questions in 5 min | email |
| kape-answers-slow | slowest 10% of answers > 10 s | email |
| kape-http-5xx | ≥ 5 server errors in 5 min | email |
| kape-backup-missing | no successful backup in 24 h | email |

### G3. First backup and restore test (on the server)
In Session Manager:
```bash
sudo /opt/kape/app/infra/ops/backup.sh
```
✅ It ends with `backup … OK`. The files appear in S3 under `backups/<time>/`: the database archive, the uploads archive, `manifest.json` and `SHA256SUMS`.
```bash
sudo /opt/kape/app/infra/ops/restore.sh --test latest
```
✅ It downloads the backup **from S3**, checks the checksums and restores into `LibreChat_restoretest`. Then it prints `expected counts` and `restored counts`, which must be identical, and deletes the test database. The live site is untouched.

**Real disaster** (database lost or corrupted): `sudo /opt/kape/app/infra/ops/restore.sh --live --yes latest`. This stops LibreChat, replaces the database and uploads (the old folders are kept as `*.before-restore-<time>`), checks the counts and starts LibreChat again. The local test took 5 seconds. Measure the real restore time on AWS: that is your RTO. Your RPO is up to 24 hours (one backup per night).

### G4. Prove the alarms email you
Trigger one on purpose, safely:
```bash
aws cloudwatch set-alarm-state --alarm-name kape-answers-failing --state-value ALARM --state-reason "Test: proving the alert email works"
```
✅ An email arrives within a minute. The alarm returns to OK at its next check (up to 5 minutes), which sends a second "OK" email.

### When an alarm fires
| Alarm | First thing to check |
|---|---|
| site-down | `curl -sI https://<site>`; EC2 instance state; `docker compose ps` in Session Manager |
| answers-failing | the dashboard's "Latest failed questions" widget: a 429 is Gemini quota, 401/403 is the key, 404 is the model name |
| memory / cpu | `docker stats --no-stream`; restart the heaviest container |
| disk-high | `df -h`, `docker system df`, `du -sh /opt/kape/backups` |
| backup-missing | `/kape/host` log stream `*/automation`; run `backup.sh` by hand |

> Stopping the instance overnight (below) makes `kape-site-down` fire and skips that night's backup. Expect those emails, or don't stop it.

---

## Everyday operations
| Task | Command |
|---|---|
| Redeploy after a `git push` | `aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript --parameters 'commands=["/opt/kape/app/infra/deploy.sh"]'` |
| Update café content | `./infra/sync-content.sh $BUCKET` (live within 5 minutes) |
| Rotate the Gemini key | `aws ssm put-parameter --name /kape-lumen/gemini-api-key --type SecureString --overwrite --value "$(read -rsp 'key: ' k; echo $k)"` (picked up within 15 minutes) |
| Stop paying for compute overnight | `aws ec2 stop-instances --instance-ids $INSTANCE_ID` (the Elastic IP still costs ~$0.005/hour) |
| Start again | `aws ec2 start-instances --instance-ids $INSTANCE_ID` |

## Gotchas
- Git Bash path rewriting: always `export MSYS_NO_PATHCONV=1` (step B2).
- If Caddy logs a certificate error, check the Elastic IP is associated and ports 80/443 are open; Caddy retries by itself.
- If the gateway logs `content_load_failed` / `AccessDenied`, compare the bucket name in SSM (`/kape-lumen/env/CONTENT_BUCKET`) with the IAM policy. That's the "permission problem" from the brief's fault catalogue.
- If the gateway says `Could not load credentials`, the instance metadata hop limit is still 1 (step E2).

## Change history
- 2026-11-06: first version, written before the first deployment.
- 2026-11-07: first deployment. Fixed the snap PATH and LibreChat folder ownership. Added Part G (monitoring, backups, restore).
