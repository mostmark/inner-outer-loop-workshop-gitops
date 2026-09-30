# Workshop tools: default .bashrc (avoids "file not found" when bash is the shell)

[ -f /etc/bashrc ] && . /etc/bashrc

if [ -n "$PS1" ]; then
  # Short prompt, as in the old workshop: /etc/bashrc sets "[user@host dir]$ ", and the host name
  # of a workspace pod (workspace<id>-<hash>-<suffix>) takes up most of the terminal line.
  PS1='\$ '

  # oc, kubectl, tkn and argocd shell completion
  for tool in oc kubectl tkn argocd; do
    command -v "$tool" > /dev/null 2>&1 && source <("$tool" completion bash 2> /dev/null)
  done
fi
