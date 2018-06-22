#!/bin/sh

echo "Running setup script"

set -e

# Unset Kubernetes variables
unset $(env | awk -F= '/^\w/ {print $1}'|grep -e '_SERVICE_PORT$' -e '_TCP_ADDR$' -e '_TCP_PROTO$' |xargs)

BASEDIR=/opt/bootstrap/base-files

# Create the required directories
mkdir -p /etc/dropbear ~/.ssh /var/log

GOTTY_SHELL=${INSTRUQT_GOTTY_SHELL:-/bin/sh}
GOTTY_PORT=${INSTRUQT_GOTTY_PORT:-15778}

# Create a clean .bash_history
rm -f ~/.bash_history && touch ~/.bash_history

# Set environment variables
export TERM=xterm-color
export PROMPT_COMMAND='history -a'


# Fix for Alpine (MUSL <-> GLIBC)
if [ -f /etc/alpine-release ]; then
  cp $BASEDIR/files/sgerrand.rsa.pub /etc/apk/keys/sgerrand.rsa.pub
  apk add -q $BASEDIR/files/glibc-2.26-r0.apk
  rm -f ~/.ash_history && ln -s ~/.bash_history ~/.ash_history
fi

# TODO: remove this when the items below succeed
if [ -f /.ssh-keys/authorized_keys ]; then
  cat /.ssh-keys/authorized_keys >> ~/.ssh/authorized_keys
  /bin/chmod -Rf 0600 ~/.ssh
fi

# Copy the SSH keys from the secret
if [ -f /.authorized-keys/authorized_keys ]; then
  cat /.authorized-keys/authorized_keys >> ~/.ssh/authorized_keys
fi

# Copy the SSH keys from the secret
if [ -f /.ssh-keys/id_rsa ]; then
  cp /.ssh-keys/* ~/.ssh/
fi

# Set the correct permissions on the SSH directory
/bin/chmod -Rf 0600 ~/.ssh

# Prettify the terminal
cp ${BASEDIR}/config/vimrc $HOME/.vimrc
cp ${BASEDIR}/config/bashrc $HOME/.bashrc
cat ${BASEDIR}/config/profile >> /etc/profile

# Copy the helper functions
chmod +x ${BASEDIR}/bin/functions/*
cp -a ${BASEDIR}/bin/functions/* /bin/
cp -a ${BASEDIR}/bin/scp /bin/scp

# Start dropbear
pgrep sshd || ${BASEDIR}/bin/dumb-init ${BASEDIR}/bin/dropbear -s -g -F -R -E >/var/log/dropbear.log &

# Defaulting to INSTRUQT_ENTRYPOINT
START_COMMAND=$INSTRUQT_ENTRYPOINT

# No ENTRYPOINT but CMD
if [ -z "$INSTRUQT_ENTRYPOINT" ] && [ -n "$INSTRUQT_CMD" ]; then
  START_COMMAND=$INSTRUQT_CMD
fi

# Both ENTRYPOINT and CMD
if [ -n "$INSTRUQT_ENTRYPOINT" ] && [ -n "$INSTRUQT_CMD" ]; then
  if [ "$INSTRUQT_ENTRYPOINT" == "/bin/sh -c"* ]; then
    START_COMMAND=$INSTRUQT_ENTRYPOINT
  else
    START_COMMAND="$INSTRUQT_ENTRYPOINT $INSTRUQT_CMD"
  fi
fi

# Check if the command is not the same as the shell
if [[ "$START_COMMAND" != "$GOTTY_SHELL" ]]; then
  if [[ "$START_COMMAND" == "/bin/sh -c"* ]]; then
    ${BASEDIR}/bin/dumb-init -- $START_COMMAND >/var/log/process.log 2>&1 &
  else
    ${BASEDIR}/bin/dumb-init -- /bin/sh -c "$START_COMMAND" >/var/log/process.log 2>&1 &
  fi
fi

echo "Setup completed, starting Gotty"

# Start Gotty
${BASEDIR}/bin/dumb-init --rewrite 2:15 --rewrite 15:9 ${BASEDIR}/bin/gotty \
        --title-format "Instruqt Shell" \
        --permit-write \
        --port $GOTTY_PORT \
        /bin/sh -c "$GOTTY_SHELL"

