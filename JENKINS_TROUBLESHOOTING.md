# Jenkins Pipeline Troubleshooting

## Issue: SSH Agent Plugin Not Found

### Error Message
```
java.lang.NoSuchMethodError: No such DSL method 'sshagent' found among steps
```

### Cause
The Jenkins SSH Agent plugin is not installed in your Jenkins instance.

### Solution 1: Install SSH Agent Plugin (Recommended)

1. Navigate to your Jenkins dashboard
2. Go to **Manage Jenkins** → **Manage Plugins**
3. Click on the **Available plugins** tab
4. Search for "SSH Agent" in the filter box
5. Check the box next to "SSH Agent Plugin"
6. Click **Install without restart**
7. Once installed, the pipeline will work with the original `sshagent` syntax

### Solution 2: Use Modified Jenkinsfile (Already Applied)

If you cannot install the SSH Agent plugin, the Jenkinsfile has been modified to use the standard `withCredentials` step with `sshUserPrivateKey` instead of `sshagent`.

#### Changes Made:
- Replaced `sshagent (credentials: ['prod-ssh'])` with `withCredentials([sshUserPrivateKey(...)])`
- Modified SSH commands to use the SSH key file directly with `-i "$SSH_KEY"`
- Updated SCP commands to use the SSH key with `-i "$SSH_KEY"`

#### Benefits:
- Works with standard Jenkins credentials plugin
- No additional plugins required
- Same functionality as the original pipeline

### Credentials Configuration

Ensure you have the following credentials configured in Jenkins:

1. **SSH Key Credential** (ID: `prod-ssh`)
   - Type: SSH Username with private key
   - Username: `kangbeef` (or your deploy user)
   - Private Key: Enter the private key for the deploy server

2. **Docker Hub Credential** (ID: `dockerhub-creds`)
   - Type: Username with password
   - Username: Your Docker Hub username
   - Password: Your Docker Hub password or access token

### Verification

After applying the fixes, run the pipeline again. It should now:
1. Pass the Preflight stage with successful SSH connection
2. Complete all subsequent stages without the sshagent error
3. Successfully deploy to your server if all other configurations are correct

### Additional Notes

- The modified Jenkinsfile maintains all the original functionality
- Environment variables and deployment steps remain unchanged
- Only the SSH authentication method has been updated
- If you later install the SSH Agent plugin, you can revert to the original syntax if preferred