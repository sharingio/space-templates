terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.7.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.19.0" # Current as of April 13th
    }
  }
}

variable "use_kubeconfig" {
  type        = bool
  default     = true
  sensitive   = true
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
}


variable "namespace" {
  type        = string
  sensitive   = true
  description = "The namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "coop"
}

locals {
  username = data.coder_workspace.ii.owner
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_provisioner" "ii" {
}

provider "docker" {
}

data "coder_workspace" "ii" {
}

resource "coder_agent" "ii" {
  arch                   = data.coder_provisioner.ii.arch
  os                     = "linux"
  login_before_ready     = false
  startup_script_timeout = 180
  startup_script         = <<-EOT
    # set -e
    # start broadwayd and emacs
    broadwayd :5 2>&1 | tee broadwayd.log &
    GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 emacs 2>&1 | tee emacs.log &
    # start ttyd / tmux
    tmux -L ii new -d -s ii -P -F "Welcome to the ${lower(data.coder_workspace.ii.name)} cooperation! Hit q to continue..." -n "${lower(data.coder_workspace.ii.name)}"
    ttyd tmux -L ii at 2>&1 | tee ttyd.log &
    # start code-server
    code-server --auth none --port 13337 | tee code-server-install.log &
    # sudo apt-get install -y novnc websockify tigervnc-standalone-server icewm kitty
    mkdir novnc && ln -s /usr/share/novnc/* novnc
    cp novnc/vnc.html novnc/index.html
    websockify -D --web=/home/ii/novnc 6080 localhost:5901
    tigervncserver -useold -desktop ${lower(data.coder_workspace.ii.name)} -SecurityTypes None -geometry 1024x768
    export DISPLAY=:1
    kitty -T "${lower(data.coder_workspace.ii.name)}" --detach --hold bash -c "cd minecraftforge && ./gradlew runClient"
    sleep 999999999
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace.ii.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.ii.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.ii.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.ii.owner_email}"
  }
}

# vnc
resource "coder_app" "minecraft" {
  subdomain    = true
  share        = "public"
  agent_id     = coder_agent.ii.id
  slug         = "minecraft"
  display_name = "Minecraft"
  icon         = "https://raw.githubusercontent.com/devoxx4kids/materials/master/workshops/minecraft/images/forge-logo.png"
  url          = "http://localhost:6080?autoconnect=true"
}



# emacs
resource "coder_app" "emacs" {
  subdomain    = true
  share        = "public"
  agent_id     = coder_agent.ii.id
  slug         = "emacs"
  display_name = "Emacs"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/0/08/EmacsIcon.svg" # let's maybe get an emacs.svg somehow
  url          = "http://localhost:8085"                                             # port 8080 + BROADWAY_DISPLAY
}

# ttyd
resource "coder_app" "ttyd" {
  subdomain    = true
  share        = "public"
  slug         = "ttyd"
  display_name = "ttyd for tmux"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/0/08/EmacsIcon.svg" # let's maybe get an emacs.svg somehow
  agent_id     = coder_agent.ii.id
  url          = "http://localhost:7681" # 7681 is the default ttyd port
}

# tmux
resource "coder_app" "tmux" {
  agent_id     = coder_agent.ii.id
  display_name = "tmux"
  slug         = "tmux"
  icon         = "https://upload.wikimedia.org/wikipedia/commons/0/08/EmacsIcon.svg" # let's maybe get an emacs.svg somehow
  command      = "tmux -L at"
  share        = "public"
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.ii.id
  slug         = "code-server"
  display_name = "code-server"
  # url          = "http://localhost:13337/?folder=/home/${local.username}"
  url  = "http://localhost:13337/?folder=/home/ii"
  icon = "/icon/code.svg"
  # share     = "owner"
  share     = "public"
  subdomain = true

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "docker_volume" "iihome" {
  name = "coop-${data.coder_workspace.ii.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coop.owner"
    value = data.coder_workspace.ii.owner
  }
  labels {
    label = "coop.owner_id"
    value = data.coder_workspace.ii.owner_id
  }
  labels {
    label = "coop.id"
    value = data.coder_workspace.ii.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coop.name_at_creation"
    value = data.coder_workspace.ii.name
  }
}

resource "docker_container" "coop" {
  count = data.coder_workspace.ii.start_count
  image = "this/minecraft:homeschool"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coop-${data.coder_workspace.ii.owner}-${lower(data.coder_workspace.ii.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.ii.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.ii.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.ii.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.iihome.name
    read_only      = false
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coop.owner"
    value = data.coder_workspace.ii.owner
  }
  labels {
    label = "coop.owner_id"
    value = data.coder_workspace.ii.owner_id
  }
  labels {
    label = "coop.id"
    value = data.coder_workspace.ii.id
  }
  labels {
    label = "coop.name"
    value = data.coder_workspace.ii.name
  }
}
