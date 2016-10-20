############################################
Welcome to Artly - Automated Repository Tool
############################################

**Artly** is a small utility for creating simple signed Debian repositories
using unattended automation. This tool was created to work around some pain
points of using `APTLY repository manager <http://aptly.info>`_ and GPG
together.

What **Artly** can do for you:

* Create Debian repositories using GPG keys without having to manage GPG
  keyrings manually.
* Take the pain out of generating GPG keys and keryrings by handling it
  trasparent to the user and generating the keys with reasonable defaults.
* Allow you to do everything on the command line without any prompts so it can
  be easily used in automation.
* Create repositories from Debian packages located both on disk as well as
  those that need to be downloaded first over HTTP/FTP protocols.


Installation
============

Currently supported installation of **Artly** is via git clone of this
repository. **Artly** has only been tested on Ubuntu 12.04 but should work on
most Linux distributions that have coreutils, bash4.3 and up, findutils,
grep, sed and few other utilities installed. You will need to install **APTLY
repository manager**.


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

   .. note::

       During the installation the ``haveged`` entropy generator should have
       already been installed and started as a service. You can check it by
       running the following command:

       .. code-block:: shell

          $ sudo service haveged status

            * haveged is running

   Now generate the GPG key using **Artly** with our demo name, comment and
   email. The key is set to expire after 1 year.

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


   You can see your keys here (please note the user only has read/write
   permissions on the private key file):

   .. code-block:: shell

        $ ls -lh --time-style=+ /tmp/artly_demo/keys

        -rw-rw-r-- 1 user user   17  keyid
        -rw------- 1 user user 5.6K  private.asc
        -rw-rw-r-- 1 user user 3.8K  public.asc


5. Create Debian repository named `artly-demo` with `main` component
   for `xenial` distribution in ``/tmp/artly_demo/repository`` and sign it with
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


   You can see content of the repository and the public key here:

   .. code-block:: shell

       $ ls -lh --time-style=+ /tmp/artly_demo/repository

         drwxrwxr-x 3 user user 4.0K  dists
         drwxrwxr-x 3 user user 4.0K  pool
         -rw-rw-r-- 1 user user 3.8K  public.asc

6. You can now host the ``/tmp/artly_demo/repository`` folder on using an HTTP
   server (Apache, Nginx, etc). How to do so is outside of the scope of this
   demo. Below we will assume you have already hosted and are serving the
   repository on http://localhost.

   You can add the hosted repository to any Debian based machine using the
   following commands:

   Add ``artly-demo`` repository to your APT sources:

   .. code-block:: shell

       $ echo 'deb http://localhost/ xenial main' \
         | sudo tee /etc/apt/sources.list.d/artly-demo.list

         deb http://localhost/ xenial main

   Add the repository public key to APT keyring:

   .. code-block:: shell

       $ wget -q http://localhost/public.asc -O- \
         | sudo apt-key add -

         OK

   Update the local package list:

   .. code-block:: shell

       $ sudo apt-get update

   You can now install any packages in the repository using ``apt-get install``
   command.


Security Concerns
=================

:Concern GPG keys generated by **Artly** are not password protected:

    **Artly** targeted usage is creating repositories using unattended
    automation. Such automation should take place in a relatively controlled
    and secure environment. Even if the private key is password protected the
    passphrase is likely to be as easily accessed as the private key itself on
    the compromised system.

    In such cases
    `GPG revoke certificates <https://www.gnupg.org/gph/en/manual/c14.html>`_
    should be used to mitigate issues of a compromised key.

    .. note::

        This may not be true for systems that use secret management software
        like `HashiCorp Vault <https://www.vaultproject.io/>`_,
        `Amazon KMS <https://aws.amazon.com/kms/>`_ or
        `Square's KeyWiz <https://square.github.io/keywhiz/>`_ and may need to
        re-adressed.

:**Concern** GPG keys are put in temporary folders during **Artly** workflow:
    **Artly** workflow includes creation of keys and keyrings which are placed,
    for a short period of time, in temporary work folders. The work folders are
    randomly named and created inside ``/tmp`` which is traditionally
    open to many users and processes.

    Additionally some of **Artly**'s  commands, such as make-key, place keys in
    the output folders in case of a successful run.

    To mitigate some of these security concerns **Artly** does the following:

    1. All GPG work folders and keys permissions are set to 600 as required by
       GPG itself. The same is true for private keys placed in the output
       folders.

    2. The ``shred`` command is used to destroy all sensitive key and keyring
       files.

    3. **Artly** tries hard to shred and remove work folders in case of both
       sucessfull and unsuccessful runs unless the ``--debug`` argument is
       specified.

    3. **Aptly** provides the ``--work-folder`` argument to all commands in
       case you specify own work folder and avoid creating folders in ``/tmp``.


Notes
=====

Artly is named after APT and APTLY utilities. It stands for Automated
Repository Tool.

At present, **Artly** uses ``aptly repo publish`` only to create the repository
and does not keep any **APTLY** information used during generation.
