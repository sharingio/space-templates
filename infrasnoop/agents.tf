resource "coder_agent" "ii" {
  # The following coder_provisioner only works if the target matches the host!
  # arch                   = data.coder_provisioner.ii.arch
  # os                     = data.coder_provisioner.ii.os
  arch                   = "amd64"
  os                     = "linux"
  login_before_ready     = true
  startup_script_timeout = 180
  dir = "~/${local.repo_folder_name}"
  startup_script         = <<-EOT
    set -e
    # Check out the git_url repo
    if test -z "${data.coder_parameter.git_url.value}"
    then
      echo "No git repo specified, skipping"
    else
      if [ ! -d "${local.repo_folder_name}" ]
      then
        echo "Cloning git repo..."
        git clone ${data.coder_parameter.git_url.value}
      fi
      cd ${local.repo_folder_name}
    fi
    # start broadwayd and emacs with provided ORG @ url
    broadwayd :5 2>&1 | tee /tmp/broadwayd.log &
    wget "${data.coder_parameter.org_url.value}"
    ORGFILE=$(basename "${data.coder_parameter.org_url.value}")
    GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 emacs $ORGFILE 2>&1 | tee /tmp/emacs.log &
    # start ttyd / tmux
    tmux new -d -s "${lower(data.coder_workspace.ii.name)}" -n "ii"
    ttyd tmux at 2>&1 | tee /tmp/ttyd.log &
    # start code-server
    mkdir ~/.config/code-server
    cat <<-EOF > ~/.config/code-server/config.yaml
    bind-addr: 127.0.0.1:8080
    auth: none
    cert: false
    disable-telemetry: true
    disable-update-check: true
    disable-workspace-trust: true
    disable-getting-started-override: true
    app-name: code
    EOF
    code-server --auth none --port 13337 | tee /tmp/code-server.log &
    echo startup_script complete | tee /tmp/startup_script.exit
    exit 0
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    # GITHUB_TOKEN        = "$${data.coder_git_auth.github.access_token}"
    SESSION_NAME        = "${lower(data.coder_workspace.ii.name)}"
    GIT_AUTHOR_NAME     = "${data.coder_workspace.ii.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.ii.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.ii.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.ii.owner_email}"
  }
  metadata {
    key          = "tmux-clients"
    display_name = "tmux clients"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      tmux list-clients -F "#{client_session}:#{client_width}x#{client_height}" | xargs echo
    EOT
  }
  metadata {
    key          = "tmux-windows"
    display_name = "tmux windows"
    interval     = 5
    timeout      = 5
    script       = <<-EOT
      #!/bin/bash
      set -e
      tmux list-windows -F "#{window_index}:#{window_name}" | xargs echo
    EOT
  }
}



resource "coder_agent" "infrasnoop" {
  arch                   = data.coder_provisioner.ii.arch
  os                     = data.coder_provisioner.ii.os
  login_before_ready     = true
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e
    # start ttyd / tmux
    # tmux new -d -s "${lower(data.coder_workspace.ii.name)}" -n "infrasnoop"
    # ttyd tmux at 2>&1 | tee /tmp/ttyd.log &
  EOT

  env = {
  }
}

# resource "coder_agent" "sideloader" {
#   arch                   = data.coder_provisioner.ii.arch
#   os                     = data.coder_provisioner.ii.os
#   login_before_ready     = true
#   startup_script_timeout = 180
#   startup_script         = <<-EOT
#     set -e
#     # start ttyd / tmux
#     # tmux new -d -s "${lower(data.coder_workspace.ii.name)}" -n "infrasnoop"
#     # ttyd tmux at 2>&1 | tee /tmp/ttyd.log &
#   EOT

#   # These environment variables allow you to make Git commits right away after creating a
#   # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
#   # You can remove this block if you'd prefer to configure Git manually or using
#   # dotfiles. (see docs/dotfiles.md)
#   env = {
#   }
# }
