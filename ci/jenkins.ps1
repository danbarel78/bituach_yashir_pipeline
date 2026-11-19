# ci/jenkins.ps1 - build, run and inspect the Jenkins controller.
#
# Windows entry point: the controller is a Docker container using the host
# Docker daemon through the mounted socket. A container-specific kubeconfig is
# generated at runtime (never committed) because the Docker Desktop API server
# listens on the host's 127.0.0.1 and the certificate only trusts "localhost".
#
# Usage:
#   pwsh ./ci/jenkins.ps1 build
#   pwsh ./ci/jenkins.ps1 up
#   pwsh ./ci/jenkins.ps1 status
#   pwsh ./ci/jenkins.ps1 logs
#   pwsh ./ci/jenkins.ps1 down          # keep the home volume
#   pwsh ./ci/jenkins.ps1 down -Purge   # also delete jobs/credentials

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('build', 'up', 'down', 'status', 'logs')]
  [string]$Action = 'up',

  [switch]$Purge,

  [string]$AdminPassword = $env:JENKINS_ADMIN_PASSWORD,

  [string]$Image = 'bituach-yashir-jenkins:local',
  [string]$Container = 'bituach-jenkins',
  [string]$Volume = 'bituach-jenkins-home'
)

# Native docker writes progress and "no such object" to stderr; with
# ErrorActionPreference=Stop, PowerShell 5.1 turns that into a terminating
# error. Keep it at Continue and check $LASTEXITCODE explicitly instead.
$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Step($message) { Write-Host "==> $message" -ForegroundColor Cyan }

function Build-Image {
  Write-Step "building $Image"
  docker build -t $Image (Join-Path $repoRoot 'ci/docker/jenkins')
  if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }
}

function New-ContainerKubeconfig {
  # Rewrite 127.0.0.1 -> host.docker.internal and pin the TLS name to
  # "localhost", which is the only DNS SAN the Docker Desktop API cert has.
  $raw = (kubectl config view --minify --raw) -join "`n"
  if (-not $raw) { throw 'kubectl config view returned nothing - is the cluster running?' }
  $raw = $raw -replace 'server: (https://127\.0\.0\.1:\d+)', "server: `$1`n    tls-server-name: localhost"
  $raw = $raw -replace 'server: https://127\.0\.0\.1:', 'server: https://host.docker.internal:'
  $path = Join-Path $env:TEMP 'bituach-jenkins-kubeconfig'
  Set-Content -Path $path -Value $raw -Encoding ascii -NoNewline
  Write-Step "kubeconfig for the container: $path"
  return $path
}

function Test-Running {
  $output = & docker inspect -f '{{.State.Running}}' $Container 2>&1
  if ($LASTEXITCODE -ne 0) { return $false }
  return (($output -join '') -replace '\s', '') -eq 'true'
}

switch ($Action) {
  'build' { Build-Image }

  'up' {
    if (Test-Running) { Write-Step "$Container already running"; break }
    & docker image inspect $Image 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Build-Image }

    if (-not $AdminPassword) { $AdminPassword = 'admin' }
    $kubeconfig = New-ContainerKubeconfig

    docker rm -f $Container *> $null
    Write-Step "starting $Container on http://localhost:8080"
    docker run -d --name $Container `
      -p 8080:8080 `
      -v "${Volume}:/var/jenkins_home" `
      -v /var/run/docker.sock:/var/run/docker.sock `
      --group-add 0 `
      -v "${kubeconfig}:/var/jenkins_home/.kube/config:ro" `
      -e "JENKINS_ADMIN_PASSWORD=$AdminPassword" `
      --restart unless-stopped `
      $Image | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'docker run failed' }

    Write-Step 'waiting for Jenkins to answer'
    for ($i = 0; $i -lt 60; $i++) {
      try {
        $response = Invoke-WebRequest -Uri 'http://localhost:8080/login' -UseBasicParsing -TimeoutSec 3
        if ($response.StatusCode -eq 200) {
          Write-Step "Jenkins is up: http://localhost:8080 (admin / $AdminPassword)"
          break
        }
      } catch { Start-Sleep -Seconds 2 }
    }
  }

  'down' {
    docker rm -f $Container *> $null
    Write-Step "container removed (home volume kept: $Volume)"
    if ($Purge) {
      docker volume rm $Volume *> $null
      Write-Step "volume $Volume deleted - jobs and credentials gone"
    }
  }

  'status' {
    docker ps --filter "name=$Container" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    try {
      $code = (Invoke-WebRequest -Uri 'http://localhost:8080/login' -UseBasicParsing -TimeoutSec 3).StatusCode
      Write-Step "HTTP $code at http://localhost:8080"
    } catch { Write-Step 'Jenkins is not answering yet' }
  }

  'logs' { docker logs -f $Container }
}