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
* Document Artly generated repositories with READMEs and HTML indexes
  containing repository setup instructions.
* Push repositories to GitHub Enterprise (or GitHub.com) to be serverd by
  GitHub Pages.


Demo
====

If a picture is worth a 1,000 words, a working demo should be worth at least a
1,000,000.

Checkout the demo repository that was created by **Artly** in 3 minutes
following the instructions in `Quickstart`_ and
`Publishing the Debian Repository to GitHub Pages`_ below.

 * https://goodwillcoding.github.io/salt16-debian-repository/


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

1. Install **Artly** using `git clone method`

   Clone the repository:

   .. code-block:: shell

        $ git clone \
            https://github.com/goodwillcoding/artly \
            /tmp/artly_demo/artly


   Install pre-requisites on Ubuntu.

   .. code:: shell

       sudo $(/tmp/artly_demo/artly/artly --ubuntu-packages)


   At the end of the installation process you should be inside
   ``/tmp/artly_demo/`` folder and be able to run **Artly** using
   ``/tmp/artly_demo/artly/artly`` command.

2. Create demo playground folder.

   .. code-block:: shell

       $ mkdir \
           --parents \
           /tmp/artly_demo
       $ cd /tmp/artly_demo

3. Download local packages, place one of them in ``debian_packages`` folder
   itself, and the rest in ``debian_packages/folder``.

   .. code-block:: shell

       $ mkdir \
           --parent \
           /tmp/artly_demo/debian_packages/folder

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

   Let's generate the GPG key using **Artly** with our demo name, comment and
   email. The key is set to expire after 1 year.

   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly make-key \
           --output-folder /tmp/artly_demo/keys \
           --name-real "Art Ly" \
           --name-comment "Key used to sign Artly demo debian repository" \
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
           --distribution "xenial" \
           --component "main" \
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

6. Publishing the repository

   You can now publish your repository in a number of ways:

   a. `Publishing the Debian Repository to a Local Apache Server`_
   b. `Publishing the Debian Repository to GitHub Pages`_


Publishing the Debian Repository to a Local Apache Server
=========================================================

1. Install Apache2 server.

   Install apache2 server package

   .. code-block:: shell

       $ sudo apt-get install apache2

    Make sure it is running

   .. code-block:: shell

      $ sudo service apache2 status

        * apache2 is running

2. Document your repository with READMes for use by humans.


   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly document-debian-repository \
           --source-folder /tmp/artly_demo/repository \
           --output-folder /tmp/artly_demo/salt16-debian-repository \
           --name "salt16" \
           --title "Salt 16 Debian Repository" \
           --url "http://localhost/salt16-debian-repository" \
           --public-key-url "http://localhost/salt16-debian-repository/public.asc" \
           --package "salt-master salt-minion" \
           --style "html"

       Created output folder: /tmp/artly_demo/salt16-debian-repository
       Created work folder: /tmp/artly-document-debian-repository.1KwNstl80Z
       Removed work folder: /tmp/artly-document-debian-repository.1KwNstl80Z
       Repository Name            :  salt16
       Repository Title           :  Salt 16 Debian Repository
       Repository Folder          :  /tmp/artly_demo/salt16-debian-repository
       Repository URL             :  http://localhost/salt16-debian-repository
       Repository Public Key URL  :  http://localhost/salt16-debian-repository/public.asc
       Repository KeyServer/KeyID :
       Repository Package         :  salt-master salt-minion
       Style                      :  html

   :Warning:

       Instructions here are for basic, **INSECURE**, non-HTTPS hosting. While
       that is fine for the repository itself as it is signed by the GPG key,
       the Public GPG key itself should be hosted on HTTPS server to avoid
       ``man-in-the-middle`` attacks.

       If your key is hosted on a GPG keyserver you can also use the
       ``--key-server-keyid`` options to provide a KeyServer and KeyID.

3. Copy the Debian repostitory into the Apache root.

   .. code-block:: shell

       $ sudo cp \
           --recursive \
           --force \
           /tmp/artly_demo/salt16-debian-repository \
           /var/www

4. You can now add the hosted repository to your Debian/Ubuntu based machine

    Visit http://localhost/salt16-debian-repository using your browser and
    follow the instructions on the page to add your repository to your machine.

   :Warning:

       http://localhost is specific to your machine. If you wish others to
       access your repository you will need to make Apache available to the
       outside. (It probably is by default, so watch out)

5. Optionally, publish your repository to GitHub Pages

     See section: `Publishing the Debian Repository to GitHub Pages`_


Publishing the Debian Repository to GitHub Pages
================================================

**Artly** provides a ``publish-github-pages`` command to allow you to easily
publish to GitHub Pages.

1. Login to your GitHub.com account at https://github.com using a browser

2. Create a new repository on GitHub.com named ``salt16-debian-repository``

   :Warning:

       Use a new repository and be aware that every time
       ``publish-github-pages`` command runs it uses ``git push --force``
       destroying all the content and the commit history.

   See Official GitHub.com Documentation on creating Github Repositories:
   https://help.github.com/articles/create-a-repo/

3. Make sure you have all the necessary configuration and permissions to use
   ``git`` to push to commit to your GitHub repository.

   Consult official GitHub.com documentation if you are not sure how.


4. Export your GitHub username into the MY_GITHUB_USERNAME variable below.
   Replace ``"<username>`` with your username.

   .. code-block:: shell

       $ export MY_GITHUB_USERNAME="<username>"

   For example, my username is ``goodwillcoding`` so my export command is

   .. code-block:: shell

       $ export MY_GITHUB_USERNAME="goodwillcoding"

5. Document your repository with READMes for use by humans using GitHub Pages
   style (``--style "github-page"``) argument.

   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly document-debian-repository \
           --source-folder /tmp/artly_demo/repository \
           --output-folder /tmp/artly_demo/salt16-debian-repository.github \
           --name "salt16" \
           --title "Salt 16 Debian Repository" \
           --url "https://${MY_GITHUB_USERNAME}.github.io/salt16-debian-repository" \
           --public-key-url "https://${MY_GITHUB_USERNAME}.github.io/salt16-debian-repository/public.asc" \
           --package "salt-master salt-minion" \
           --style "github-pages"

       Created output folder: /tmp/artly_demo/salt16-debian-repository.github
       Created work folder: /tmp/artly-document-debian-repository.PMfEe1aOox
       Removed work folder: /tmp/artly-document-debian-repository.PMfEe1aOox
       Repository Name            :  salt16
       Repository Title           :  Salt 16 Debian Repository
       Repository Folder          :  /tmp/artly_demo/salt16-debian-repository.github
       Repository URL             :  https://goodwillcoding.github.io/salt16-debian-repository
       Repository Public Key URL  :  https://goodwillcoding.github.io/salt16-debian-repository/public.asc
       Repository KeyServer/KeyID :
       Repository Package         :  salt-master salt-minion
       Style                      :  github-pages

6. Push the Debian repository to your GitHub repository. You will need to
   replace ``<username>`` in the command with your

   .. code-block:: shell

       $ /tmp/artly_demo/artly/artly publish-github-pages \
           --source-folder /tmp/artly_demo/salt16-debian-repository.github \
           --git-uri "git@github.com:${MY_GITHUB_USERNAME}/salt16-debian-repository.git" \
           --author "${MY_GITHUB_USERNAME}" \
           --email "${MY_GITHUB_USERNAME}@example.com" \
           --title "Salt 16 Debian Repository"

7. Publish your Debian repository to GitHub Pages itself.

    .. note::

       Configuring repository to publish to GitHub Pages as described below
       only need to be done ONCE as settings are retained.

   Go to GitHub.com ``salt16-debian-repository.git`` repository settings,
   scroll to **GitHub Pages** section.

   For GitHub Pages **Source** pick **master branch** from the dropdown and
   press safe.

   It will take a couple of minutes for the your repository's GitHub Pages
   to be built.

8. Add the hosted repository to your Debian/Ubuntu based machine

   Visit ``https://<username>.github.io/salt16-debian-repository`` using your
   browser and follow the instructions on the page to add your repository
   to your machine.


Security Concerns
=================

:GPG keys generated by **Artly** are not password protected:

    **Artly** targeted usage is creating repositories using unattended
    automation. Such automation should take place in a relatively controlled
    and secure environment. Even if the private key is password protected the
    passphrase is likely to be as easily accessed as the password file used to
    unlock the key if the system it is on is compromised.

    In such cases
    `GPG revoke certificates <https://www.gnupg.org/gph/en/manual/c14.html>`_
    should be used to mitigate issues of a compromised key.

    .. note::

        This may not be true for systems that use secret management software
        like `HashiCorp Vault <https://www.vaultproject.io/>`_,
        `Amazon KMS <https://aws.amazon.com/kms/>`_ or
        `Square's KeyWiz <https://square.github.io/keywhiz/>`_ and may need to
        re-adressed.

:GPG keys are put in temporary folders during **Artly** workflow:

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

    4. **Artly** provides the ``--work-folder`` argument to all commands in
       case you specify own work folder and avoid creating folders in ``/tmp``.


Notes
=====

Artly is named in the fashion of APT and APTLY utilities. It stands for
Automated Repository Tool.

At present, **Artly** uses ``aptly repo publish`` only to create the repository
and does not keep any **APTLY** information used during generation.
