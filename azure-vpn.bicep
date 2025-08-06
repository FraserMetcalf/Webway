@description('Container instance location to deploy as Tailscale [exit node](https://tailscale.com/kb/1103/exit-nodes).')
// az provider show -n Microsoft.ContainerInstance --query "resourceTypes[?resourceType=='containerGroups'].locations | [0]" --output tsv
@allowed(['australiacentral','australiacentral2','australiaeast','australiasoutheast','brazilsouth','canadacentral','canadaeast'
'centralindia','centralus','eastasia','eastus','eastus2','francecentral','francesouth','germanynorth','germanywestcentral'
'israelcentral','italynorth','japaneast','japanwest','koreacentral','koreasouth','mexicocentral','newzealandnorth','northcentralus'
'northeurope','norwayeast','norwaywest','polandcentral','qatarcentral','southafricanorth','southafricawest','southcentralus'
'southeastasia','southindia','spaincentral','swedencentral','switzerlandnorth','switzerlandwest','uaecentral','uaenorth','uksouth'
'ukwest','westcentralus','westeurope','westindia','westus','westus2','westus3'])
param location string

@description('''Tailscale [OAuth client](https://tailscale.com/kb/1215/oauth-clients) secret, must have `auth_keys` and `devices:core`
 scopes and be assigned a tag with a value equal to the param `tailscaleTag` e.g. `tag:exitnode`.''')
@secure()
#disable-next-line secure-parameter-default
param tailscaleClientSecret string

@description('''Tailscale tag to advertise as exit node. Must be defined in Tailscale policy 
[tagOwners](https://tailscale.com/kb/1337/acl-syntax#tag-owners), 
[autoApprovers.exitNode](https://tailscale.com/kb/1337/acl-syntax#autoapprovers).''')
param tailscaleTag string = 'tag:exitnode'

@description('The geolocation of the data centre you are locating the node in')
param country string 

resource aci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'aci-tailscale-${location}'
  location: location
  properties: {
    sku: 'Standard'
    osType: 'Linux'
    restartPolicy: 'Never'
    ipAddress: {
      type: 'Public'
      ports: [
        // help Tailscale make a peer-to-peer connection rather than falling back to a relay
        // https://tailscale.com/kb/1082/firewall-ports#my-devices-are-using-a-relay-what-can-i-do-to-help-them-connect-peer-to-peer
        {
          protocol: 'UDP'
          port: 41641
        }
      ]
    }
    containers: [
      {
        name: 'tailscale'
        properties: {
          // https://github.com/microsoft/azurelinux
          // https://mcr.microsoft.com/en-us/artifact/mar/azurelinux/base/core/about
          image: 'mcr.microsoft.com/azurelinux/base/core:3.0'
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 1
            }
          }
          ports: [
            {
              protocol: 'UDP'
              port: 41641
            }
          ]
          environmentVariables: [
            {
              name: 'TAILSCALE_LOCATION'
              value: location
            }
            {
              name: 'TAILSCALE_TAG'
              value: tailscaleTag
            }
            {
              name: 'TAILSCALE_CLIENT_SECRET'
              secureValue: tailscaleClientSecret
            }
            {
              name: 'NODE_COUNTRY'
              value: country
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            join([
              // prerequisites to download tailscale
              'tdnf update -yq && tdnf -yq install ca-certificates jq'
              // download latest tailscale and extract to bin
              'echo "Installing Tailscale..."'
              'curl -fsSL "https://pkgs.tailscale.com/stable/$(curl -fsSL "https://pkgs.tailscale.com/stable/?mode=json" | jq -r ".Tarballs.amd64")" | bsdtar -xvzf - -C /usr/bin --strip-components 1 "*/tailscale" "*/tailscaled"'
              // run tailscaled in the background with in-memory state
              // and userspace networking mode https://tailscale.com/kb/1112/userspace-networking
              // https://tailscale.com/kb/1278/tailscaled
              'echo "Starting Tailscale service..."'
              'tailscaled --state=mem: --tun=userspace-networking 2>/var/log/tailscaled.log &'
              // wait for tailscaled to start
              // json will make it exit with status 0 even if logged out
              'tailscale status --json >/dev/null'
              // report current version including daemon version
              'tailscale version --daemon'
              // connect to tailnet with exit node configuration
              // https://tailscale.com/kb/1241/tailscale-up
              'echo "Connecting to Tailscale..."'
              'tailscale up --hostname="WebwayGate-$NODE_COUNTRY" --authkey="$TAILSCALE_CLIENT_SECRET?preauthorized=true&ephemeral=true" --accept-dns="false" --advertise-exit-node --advertise-tags="$TAILSCALE_TAG"'
              'echo "Connected to Tailscale"'
              // report network health
              'tailscale netcheck'
              // follow the log file to stdout
              'tail -f /var/log/tailscaled.log &'
              // on termination deregister the exit node
              'trap "tailscale down" SIGTERM'
              // keep the container running until terminated
              'sleep infinity &'
              'pid=$!'
              'wait $pid'
              'echo "Disconnecting from Tailscale..."'
              'tailscale down'
              'echo "Disconnected from Tailscale"'
            ], '\n')
          ]
        }
      }
    ]
  }
}
