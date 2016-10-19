############################################
Welcome to Artly - Automated Repository Tool
############################################

**Artly** is small utility for creating simple signed Debian repositories in an
from unattended automation setups using GPG and `APTLY <http://aptly.info>`_.
**Artly** was partly created mainly to work around some pain points that come
up when using GPGP for repository signing.

What **Artly** can do for you:

* Take the pain out of generating GPG key(s) and generating those key(s) with
  reasonable defaults.
* Create Debian repositories using those key(s) without having to manage GPG
  keyrings manually.
* Do everything on command line without prompts so it can be easily used in
  automation.
* Create repositories from Debian packages or folder containing on disk and
  downloaded using ``wget`` utility over HTTP/FTP protocols.


Installation
============

Current supported installation is on via git clone of this repository. Only
tested OS so far has been Ubuntu 12.04 and up but it should work on most Linux
distributions. You will also need a number of tools such as bash4, find, grep,
sed and so on. And, of course, you will need to install **APTLY**.

1. Install **APTLY** using official instructions here:
   https://www.aptly.info/download/
2. Clone the **Artly** repostory

   .. code:: shell

       $ git clone https://github.com/goodwillcoding/artly
       $ cd artly

3. Print out which packages you will need as prerequisites of **Artly**

   .. code:: shell

       $ ./artly --ubuntu-packages

   If you trust the output then you can run the install with sudo.

   .. code:: shell

       sudo $(./artly --ubuntu-packages)


Quickstart
==========

Let's create some keys and a create a small Debian repository with 3 different
Debian sources: local package, local folder containing multiple packages and
URLs to 2 Debian packages.


1. Create demo playground folder.

   .. code-block:: shell

       $ mkdir --parents /tmp/artly_demo
       $ cd /tmp/artly_demo


2. Use installation instruction above to install **Artly** into the
   ``/tmp/artly_demo/artly`` folder using ``git clone``.

   At the end of the installation process you should be inside
   ``/tmp/artly_demo/`` folder and be able to run **Artly** using
   ``/tmp/artly_demo/artly/artly`` command.

3. Download local packages, place one of them in ``debian_packages`` folder
   itself, and the rest in ``debian_packages/folder``.

   .. code-block:: shell

       $ mkdir --parent /tmp/artly_demo/debian_packages/folder

       $ wget \
           --no-clobber \
           --directory-prefix "/tmp/artly_demo/debian_packages" \
             http://mirrors.kernel.org/ubuntu/pool/universe/p/python-support/python-support_1.0.14ubuntu2_all.deb

       $ wget \
           --no-clobber \
           --directory-prefix "/tmp/artly_demo/debian_packages/folder" \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt-common_0.16.4-1precise_all.deb \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt-master_0.16.4-1precise_all.deb \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt-minion_0.16.4-1precise_all.deb \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt-syndic_0.16.4-1precise_all.deb \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt_0.16.4-1precise.dsc \
           https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt_0.16.4-1precise.tar.gz

4. Create new GPG keys using **Artly** and place it in ``/tmp/artly_demo/keys``
   folder.

   During the installation the ``haveged`` entropy generation should have being
   installed and it's service running. Please check that it is running by
   running the following:

   .. code-block:: shell

      $ sudo service haveged status

         * haveged is running

   Now generate the GPG key using **Artly** with our demo name, comment and
   email. The key is set to expire after 1yr.

   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly make-key \
           --output-folder /tmp/artly_demo/keys \
           --name-real "Art Ly" \
           --name-comment "Key used to sign a demo debian repository" \
           --name-email "artly@example.com" \
           --expire-date 1y

         Created output folder: /tmp/artly_demo/keys
         Created work folder: /tmp/artly-make-key.ZdqbU4cobW
         Available entropy: 2123
         If you entropy is low this may take a while. Make sure you have "haveged" service running
         Shredded and removed work folder: /tmp/artly-make-key.ZdqbU4cobW
         Private key: /tmp/artly_demo/keys/private.asc
         Public key : /tmp/artly_demo/keys/public.asc
         KeyID      : B3DD55841FD14286
         KeyID file : /tmp/artly_demo/keys/keyid
         GPG version: gpg (GnuPG) 1.4.11


   You can see your keys here (note the user only read/write permission on the
   private key file):

   .. code-block:: shell

        $ ls -lh --time-style=+ /tmp/artly_demo/keys

        -rw-rw-r-- 1 user user   17  keyid
        -rw------- 1 user user 5.6K  private.asc
        -rw-rw-r-- 1 user user 3.8K  public.asc


5. Create Debian repository named `artly-demo` with `main` component
   for `xenial` distribution in ``/tmp/artly_demo/repository``. Sign it with
   ``./keys/private.asc`` public key.

   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly make-debian-repository \
           --output-folder /tmp/artly_demo/repository \
           --name "artly-demo" \
           --component "main" \
           --distribution "xenial" \
           --secret-key-file /tmp/artly_demo/keys/private.asc \
           --package-location "/tmp/artly_demo/debian_packages/folder" \
           --package-location "/tmp/artly_demo/debian_packages/python-support_1.0.14ubuntu2_all.deb" \
           --package-location "/tmp/artly_demo/debian_packages/python-support_1.0.14ubuntu2_all.deb" \
           --package-url "https://launchpad.net/~saltstack/+archive/ubuntu/salt16/+files/salt-doc_0.16.4-1precise_all.deb"

         Created work folder: /tmp/artly-make-debian-repository.TcOJOl9btX
         Saving to: `/tmp/artly-make-debian-repository.TcOJOl9btX/packages_source/salt-doc_0.16.4-1precise_all.deb`
         100%[=================================================================================>] 3,479,210 in 9.5s
         Created output folder: /tmp/artly_demo/repository
         Shredded and removed work folder: /tmp/artly-make-debian-repository.TcOJOl9btX
         Repository Name            : artly-demo
         Repository Component       : main
         Repository Distribution    : xenial
         Repository Architectures   : amd64,i386,all,source
         Repository Folder          : /tmp/artly_demo/repository
         Repository Label           :
         Repository Origin          :
         GPG version                : gpg (GnuPG) 1.4.11
         Public Key                 : /tmp/artly_demo/repository/public.asc
         Repository Package Count   : 7


   You can see content of the repository and the private key for it here:

   .. code-block:: shell

       $ ls -lh --time-style=+ /tmp/artly_demo/repository

         drwxrwxr-x 3 user user 4.0K  dists
         drwxrwxr-x 3 user user 4.0K  pool
         -rw-rw-r-- 1 user user 3.8K  public.asc

6. You can now host that folder on your HTTP server using Apache or Nginx.
   How to do so is outside of the scope of this demo. Assuming you have now
   hosted the repository on http://localhost you can add it to any Debian based
   distribution using following commands:

   Add ``artly-demo`` repository to your APT sources

   .. code-block:: shell

       $ echo 'deb http://localhost/ xenial main' \
         | sudo tee /etc/apt/sources.list.d/artly-demo.list

         deb http://localhost:9000/ xenial main

   Add the repository public key:

   .. code-block:: shell

       $ wget -q http://localhost/private.asc -O- \
         | sudo apt-key add -

         OK

   Update the package list:

   .. code-block:: shell

       $ sudo apt-get update

   You can now install any packages in the repository using ``apt-get install``
   command.


On Security
===========

:GPG keys generated by **Artly** are not password protected:
    **Artly** targeted usage is creating repositories using unattended
    automation. Such automation should take place in relatively controlled and
    secure  environment. Even if the private key is password protected the
    passphrase is likely to be as easily accessed as the private key itself on
    the compromised system.

    In such cases
    `GPG revoke certificates <https://www.gnupg.org/gph/en/manual/c14.html>`_
    should be used to mitigate issues of a compromised key.

:GPG keys are put in temporary folders when during **Artly** workflow:
    **Artly** workflow includes creation of keys and keyring in temporary work
    folders as well as placing keys in the output folders for some of the
    command (i.e. make-key). The files and folder are created in randomly named
    folders inside ``/tmp``. To mitigate these concerns **Artly** does the
    following:

    1. All GPG work folder and keys permissions are set to 600 as required by
       GPG itself. Same is true for the output folders where the private keys
       are placed.

    2. The ``shred`` command is used to destroy all sensitive key and keyring
       files.

    3. **Aptly** provides ``--work-folder`` argument to all commands in case
       you specify the to avoid creating folders in ``/tmp``.


Notes
=====

Artly is named after APT and APTLY and stands for Automated Repository Tool

At present, **Artly** uses ``aptly repo publish`` only to create the repository
and does not keep any **APTLY** information behind.
