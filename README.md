# Host your own global VPN on Azure PaaS using Tailscale

Stolen directly from https://gist.github.com/maskati/446d72d751f90c4539db3adc4a7a664e
Unfortunately I forked this in a really janky way (including some fiddling on my phone for some reason), so I ended up uploading my new version as a direct upload and thus the fork link is broken.

This example shows setting up a Tailscale [exit node](https://tailscale.com/kb/1103/exit-nodes) running as a container on Azure Container Instances to provide global Internet egress. You can also use a similar setup to configure a Tailscale [subnet router](https://tailscale.com/kb/1019/subnets) which would allow access to Azure private Virtual Networks, private endpoints, private DNS zone resolution as well as Azure service endpoints.

You can use exit nodes on [several platforms](https://tailscale.com/kb/1347/installation#install-and-update-instructions) including Android, iOS, Linux, macOS, tvOS and Windows.

> [!WARNING]
> Using an exit node will tunnel all your traffic through the selected Azure region. This might trigger certain security controls such as Entra ID protection [impossible travel](https://learn.microsoft.com/en-us/entra/id-protection/concept-identity-protection-risks#impossible-travel).

> [!NOTE]
> This deployment uses a [Microsoft Artifact Registry](https://mcr.microsoft.com/) published [Azure Linux](https://github.com/microsoft/azurelinux) image with a scripted installation of Tailscale. This is done instead of using the ready [Tailscale image](https://hub.docker.com/r/tailscale/tailscale) published on Docker Hub due to Docker [anonymous uage limits](https://docs.docker.com/docker-hub/usage/).

## Deployment

### Step 1: Sign-up for Tailscale

[Sign-up](https://login.tailscale.com/start) for a free Tailscale [personal plan](https://tailscale.com/pricing?plan=personal). The free plan supports up to 3 users and 100 devices.

### Step 2: Configure your Tailscale policy

Define a Tailscale [ACL policy](https://tailscale.com/kb/1018/acls) in the [access controls](https://login.tailscale.com/admin/acls/file) section of the admin portal:

```json
{
  "tagOwners": {
    "tag:exitnode": [],
  },
  "autoApprovers": {
    "exitNode": ["tag:exitnode"],
  },
  "acls": [
    {
      "action": "accept",
      "src":    ["*"],
      "dst":    ["*:*"],
    },
  ],
}
```

### Step 3: Create an OAuth client

Create a Tailscale [OAuth client](https://tailscale.com/kb/1215/oauth-clients) in the [OAuth clients settings](https://login.tailscale.com/admin/settings/oauth) section of the admin portal. Configure the OAuth client as follows:
- Description a descriptive name e.g. `Azure VPN`
- Scope Keys -> Auth Keys -> Write (`auth_keys`) with the assigned tag `tag:exitnode`. This allows the OAuth client to exchange the client secret for an authentication key to [register the node with using OAuth credentials](https://tailscale.com/kb/1215/oauth-clients#registering-new-nodes-using-oauth-credentials).
- Scope Devices -> Core -> Write (`devices:core`) with the assigned tag `tag:exitnode`. This allows the OAuth client to register and [auto approve](https://tailscale.com/kb/1337/acl-syntax#auto-approvers) itself as a device.

After creation of the client you will be shown a client ID and client secret. The client secret is of the form `tskey-client-<clientid>-<secret>`. You will need the client secret for the `tailscaleClientSecret` deployment parameter in the next step.

### Step 4: Deploy to Azure

Deploy the Bicep [azure-vpn.bicep](#file-azure-vpn-bicep) or click the button below to deploy the compiled ARM template [azure-vpn.json](#file-azure-vpn-json). Configure parameters:
- `Region` not really relevant, this is the region for your resource group metadata
- `Location` which region to deploy the Azure Container Instance to serve as the VPN exit node
- `Tailscale Client Secret` the OAuth client secret from the previous step
- `Tailscale Tag` can be left as `tag:exitnode` if you did not change this in the earlier configuration steps

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FFraserMetcalf%2FWebway%2Frefs%2Fheads%2Fmain%2Fazure-vpn.json)

> [!TIP]
> Repeat with different `Location` values to deploy exit nodes at different Azure regions around the world.

An example with various regions deployed:

![image](https://gist.github.com/user-attachments/assets/f964464b-2ebc-4a62-bfa3-b3a89bee3dc2)

## Using the VPN

You can [use the exit node](https://tailscale.com/kb/1408/quick-guide-exit-nodes#use-an-exit-node) by selecting the Tailscale icon and navigating to *Use exit node* then selecting the name of the exit node device.

![image](https://gist.github.com/user-attachments/assets/4b30d7fc-5f35-4e3a-aaa4-125e617df296)

Performing an IP lookup when connected to the Azure East Japan region:

![image](https://gist.github.com/user-attachments/assets/28b2431c-0468-4886-a030-ceeb799a11ae)

## Clean up

1. Stop and delete the Azure Container Instances.
2. Ensure exit node devices are deregistered in the Tailscale admin [machines listing](https://login.tailscale.com/admin/machines).
3. If desired [revoke the OAuth client](https://tailscale.com/kb/1215/oauth-clients#revoking-an-oauth-client).
