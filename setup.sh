#!/bin/sh

set -e

# Unset Kubernetes variables
unset $(env | awk -F= '/^\w/ {print $1}'|grep -e "_HOST" -e "_PORT" |xargs)

BASEDIR=/opt/bootstrap/base-files

# Create the required directories
mkdir -p /etc/dropbear /root/.ssh

if [ ! -e "$INSTRUQT_GOTTY_SHELL" ]; then
  INSTRUQT_GOTTY_SHELL=/bin/sh
fi


if [ ! -e "$INSTRUQT_GOTTY_PORT" ]; then
  INSTRUQT_GOTTY_PORT=15778
fi


# Create a clean .bash_history
rm -f /root/.bash_history && touch /root/.bash_history

# Set environment variables
export TERM=xterm
export PROMPT_COMMAND='history -a'
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export ENV=/root/.bashrc


# Fix for Alpine (MUSL <-> GLIBC)
if [ -f /etc/alpine-release ]; then
  cp $BASEDIR/files/sgerrand.rsa.pub /etc/apk/keys/sgerrand.rsa.pub
  apk add -q $BASEDIR/files/glibc-2.26-r0.apk
  rm -f /root/.ash_history && ln -s /root/.bash_history /root/.ash_history
fi

# TODO: remove this when the items below succeed
if [ -f /.ssh-keys/authorized_keys ]; then
  cat /.ssh-keys/authorized_keys >> /root/.ssh/authorized_keys
  /bin/chmod -Rf 0600 /root/.ssh
fi

# Copy the SSH keys from the secret
if [ -f /.authorized-keys/authorized_keys ]; then
  cat /.authorized-keys/authorized_keys >> /root/.ssh/authorized_keys
fi

# Copy the SSH keys from the secret
if [ -f /.ssh-keys/id_rsa ]; then
  cp /.ssh-keys/* /root/.ssh/
fi

# Set the correct permissions on the SSH directory
/bin/chmod -Rf 0600 /root/.ssh



# Prettify the terminal
cp ${BASEDIR}/config/vimrc /root/.vimrc
cp ${BASEDIR}/config/bashrc /root/.bashrc
cp ${BASEDIR}/config/bash_functions /root/.bash_functions
cp ${BASEDIR}/config/bash_profile /root/.bash_profile

# Start dropbear
pgrep sshd || ${BASEDIR}/bin/dumb-init ${BASEDIR}/bin/dropbear -s -g -F -R -E >/var/log/dropbear.log &

# Start the entrypoint of the user but only if it is different from the shell
if [ -n "$INSTRUQT_ENTRYPOINT" ] && [ "$INSTRUQT_ENTRYPOINT" != "$INSTRUQT_GOTTY_SHELL" ]; then
    ${BASEDIR}/bin/dumb-init -- /bin/sh -c "$INSTRUQT_ENTRYPOINT $INSTRUQT_CMD" >/var/log/process.log 2>&1 &
fi

# Start the CMD of the user but only if it is different from the shell
if [ -n "$INSTRUQT_CMD" ] &&  [ "$INSTRUQT_CMD" != "$INSTRUQT_GOTTY_SHELL" ]; then
    ${BASEDIR}/bin/dumb-init -- /bin/sh -c "$INSTRUQT_CMD" >/var/log/process.log 2>&1 &
fi

# Start Gotty
${BASEDIR}/bin/dumb-init --rewrite 2:15 --rewrite 15:9 ${BASEDIR}/bin/gotty \
        --title-format "Instruqt Shell" \
        --permit-write \
        --port $INSTRUQT_GOTTY_PORT \
        /bin/sh -c "$INSTRUQT_GOTTY_SHELL"
