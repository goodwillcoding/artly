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

SIGNERS_GPG_KEYID=${SIGNERS_GPG_KEYID:-};

if [ "${SIGNERS_GPG_KEYID}" == "" ]; then
  echo "Please set SIGNERS_GPG_KEYID to a valid key id in the current keyring"
  exit 1;
fi

# ........................................................................... #
LOCAL_GPG2_AGENT_EXTRA_SOCKET=${LOCAL_GPG2_AGENT_EXTRA_SOCKET:-};

# get the gpg2 socket on the host machine
if [ "${LOCAL_GPG2_AGENT_EXTRA_SOCKET}" == "" ]; then
  TMP_GPG2_AGENT_EXTRA_SOCKET=$(\
      gpgconf --list-dir \
      | grep '^agent-extra-socket:' \
      | cut -d':' -f2) || true;

  if [ "${TMP_GPG2_AGENT_EXTRA_SOCKET}" == "" ]; then
      echo "\
Failed to get GPG2 agent-extra-socket using gpgconf, you must have a pre 2.1.13
GPG2 version. please configure gpg-agent.conf to have extra-socket.
  Example: extra-socket /home/<user>/.gnupg/S.gpg-agent-extra
Then export LOCAL_GPG2_AGENT_EXTRA_SOCKET='<path to socket>' before running
this script.

  Read more here: https://wiki.gnupg.org/AgentForwarding
";
    exit 1;
  else
    LOCAL_GPG2_AGENT_EXTRA_SOCKET="${TMP_GPG2_AGENT_EXTRA_SOCKET}";
  fi
fi

# ........................................................................... #
SIGNERS_GPG_KEYID_FINGERPRINT=$(\
  gpg2 \
    --fingerprint \
    --with-colons \
    "${SIGNERS_GPG_KEYID}" \
  | grep "^fpr:::::::::[0-9ABCDEF]*${SIGNERS_GPG_KEYID}:" \
  | sed 's/\://g' \
  | cut -c4- ) || true;

if [ "${SIGNERS_GPG_KEYID_FINGERPRINT}" == "" ]; then
  echo "Failed to get finger print for key: ${SIGNERS_GPG_KEYID}";
  exit 1;
fi


# ........................................................................... #
# reload the gpg agent on the host machine, clearing cache
# just in case. However the best way is to set default-cache-ttl 0 and
# max-cache-ttl 0 in your gpg-agent.conf, since the keys are being accessed
# outside your machine
echo "reloading host machine gpg-agent, forgetting any cached passphrases: \
$(gpg-connect-agent reloadagent /bye)";


# ........................................................................... #
echo "vagrant: aliasing gpg command to gpg2"
echo "vagrant: killing all gpg-agent process for the vagrant user"
echo "vagrant: removing /home/vagrant/.gnupg"
echo "vagrant: creating /home/vagrant/.gnupg"
vagrant ssh \
    --command "\
    echo alias gpg=gpg2 > ~/.bash_aliases; \
    killall gpg-agent 2>/dev/null || true; \
    rm --recursive --force ~/.gnupg
    gpg2 --no-autostart --quiet --list-keys 2>/dev/null || true;" \
2>/dev/null


# ........................................................................... #
echo "vagrant: importing public key of the private key that will be used to sign"
echo "vagrant: trusting public key of the private key that will be used to sign"
# kill the agent after import and trust
gpg2 \
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
  -R /home/vagrant/.gnupg/S.gpg-agent:"${LOCAL_GPG2_AGENT_EXTRA_SOCKET}"



