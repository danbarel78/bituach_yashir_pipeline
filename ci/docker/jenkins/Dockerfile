# Jenkins controller for the Bituach Yashir POC.
#
# One container, no agents: the controller builds and pushes images using the
# host's Docker daemon through the mounted socket. That is a POC shortcut and
# is documented as such (production: Kaniko / dedicated build agents).
#
# Everything is pinned. Bump the ARGs deliberately; never `latest`.
FROM jenkins/jenkins:lts-jdk21

USER root

ARG DOCKER_CLI_VERSION=27.5.1
ARG BUILDX_VERSION=0.39.0
ARG KUBECTL_VERSION=1.36.1
ARG TRIVY_VERSION=0.76.2
ARG UV_VERSION=0.13.9

# Base tooling. python3 is used by ci/scripts/version.py (stdlib only);
# uv installs Python 3.12 on demand for the services.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq python3 unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only - the daemon stays on the host.
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" \
      | tar -xz --strip-components=1 -C /usr/local/bin docker/docker \
    && docker --version

# buildx: the service Dockerfiles use BuildKit cache mounts, and the Docker CLI
# refuses BuildKit when the plugin is missing.
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSLo /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx \
    && docker buildx version

# kubectl, used to wait for Argo CD and to render kustomize overlays.
RUN curl -fsSLo /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && kubectl version --client

# Trivy: image vulnerability gate.
RUN curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
      | tar -xz -C /usr/local/bin trivy \
    && trivy --version

# uv: dependency manager + Python 3.12 provider.
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_VERSION=${UV_VERSION} sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && uv --version

# Plugins are resolved by jenkins-plugin-cli against the Jenkins core version.
# Pin them explicitly once the first build has proven the set (see README).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration as code + job bootstrap (copied into JENKINS_HOME on first run).
COPY jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/jenkins.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.model.DownloadService.noSignatureCheck=true"

USER jenkins