0.2 (in development)
====================

Features
--------

 * Added 'document-debian-repository' command which when given a repository
   documents it with READMEs on how to setup the repository on users machine
   and generates html index for directories. This makes the repository much
   more human friendly. Supports 2 styles: 'html' and 'github-pages'.
   The 'html' style is suited to be served by Apache/Nginx with index file
   being set to "index.html" (default in most installations.)
   The 'github-pages' style is designed for the 'publish-github-pages' command
   (see below) by adding a GitHub friendly Readme.md

 * Added 'publish-github-pages' command which allows a user to push the
   package repository to a GitHub repository master branch. The GitHub git
   repository can then be configured to server the server the pushed package
   repository as a GitHub Pages site. Best use is with the
   'document-debian-repository' command (described above) when it is run with
   '--style github-pages' argument

Bugs
----

* Fixed a critical bug in all commands that created output folder where the
  output folder would get removed even if was not created by the script.
* For "make-debian-repository" now copy the aptly repository over, do not move
  it from the temporary aptly folder.
* Various small clean ups and documentation updates for the code

0.1.1 (2016-12-21)
==================

* Clean up a few error string that referenced non-existent '-r' argument for
  all the scripts

0.1 (2016-10-18)
================

- Initial release or artly
- make-key and make-debian-repository commands made available
