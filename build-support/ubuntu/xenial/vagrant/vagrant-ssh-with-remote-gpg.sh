#! /usr/bin/env bash

# https://wiki.gnupg.org/AgentForwarding
# http://code.v.igoro.us/posts/2015/11/remote-gpg-agent.html
# https://fedoraproject.org/wiki/Creating_GPG_Keys

# ........................................................................... #
# turn on tracing of error, this will bubble up all the error codes
set -o errtrace;
# turn on quiting on first error
set -o errexit;
# error out on undefined variables
set -o nounset;
# propagate pipe errors
set -o pipefail;
# debugging
#set -o xtrace;

# TODO: need to check the gpg2 version

# ........................................................................... #
# export the gpg key
#SIGNERS_GPG_KEYID=232243A0C68184A0

SIGNERS_GPG_KEYID=${SIGNERS_GPG_KEYID:-}

if [ "${SIGNERS_GPG_KEYID}" == "" ]; then
  echo "Please set SIGNERS_GPG_KEYID to a valid key id in the current keyring"
  exit 1;
fi

# ........................................................................... #
SIGNERS_GPG_KEYID_FINGERPRINT=$(\
  gpg2 \
    --fingerprint \
    --with-colons \
    "${SIGNERS_GPG_KEYID}" \
  | grep '^fpr:::::::::[0-9ABCDEF]*232243A0C68184A0:' \
  | sed 's/\://g' \
  | cut -c4- )

# ........................................................................... #
# get the gpg2 socket on the host machine
TMP_GPG_AGENT_EXTRA_SOCKET=$(\
    gpgconf --list-dir \
    | grep '^agent-extra-socket:' \
    | cut -d':' -f2)


# ........................................................................... #
# reload the gpg agent on the host machine, clearing cache
# just in case. However the best way is to set default-cache-ttl 0 and
# max-cache-ttl 0 in your gpg-agent.conf, since the keys are being accessed
# outside your machine
echo "reloading host machine gpg-agent, forgetting any cached passphrases: \
$(gpg-connect-agent reloadagent /bye)";


# ........................................................................... #
echo "aliasing gpg command to gpg2"
echo "killing all gpg-agent process for the vagrant user"
echo "removing /home/vagrant/.gnupg"
echo "creating /home/vagrant/.gnupg"
vagrant ssh \
    --command "\
    echo alias gpg=gpg2 > ~/.bash_aliases; \
    killall gpg-agent 2>/dev/null || true; \
    rm --recursive --force ~/.gnupg
    gpg2 --no-autostart --quiet --list-keys 2>/dev/null || true;" \
2>/dev/null


# ........................................................................... #
echo "importing public key of the private key that will be used to sign"
echo "trusting public key of the private key that will be used to sign"
# kill the agent after import and trust
gpg \
  --armor \
  --export \
  "${SIGNERS_GPG_KEYID}" \
| vagrant ssh \
    --command "\
    gpg2 --no-autostart --quiet --import 2>/dev/null; \
    echo ${SIGNERS_GPG_KEYID_FINGERPRINT}:6: \
    | gpg2 --import-ownertrust 2>/dev/null;"


# ........................................................................... #
echo "mapping local GPG extra socket mapped to one used by vagrant user"
echo "logging in to the vagrant box"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vagrant ssh \
  --command "\
  gpg-connect-agent --no-autostart nop /bye;
  sleep 3;
  cd /tmp/artly;
  make clean;
  SIGNERS_GPG_KEYID=${SIGNERS_GPG_KEYID} \
    make ubuntu-xenial-packages;
  " \
  -- \
  -R /home/vagrant/.gnupg/S.gpg-agent:"${TMP_GPG_AGENT_EXTRA_SOCKET}"



