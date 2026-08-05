#!/bin/bash
# ============================================================================
# install_dependencies.sh  -  CODEDEPLOY HOOK: BeforeInstall
#
# RUNS SECOND in the deployment lifecycle:
#   1. ApplicationStop    stop_server.sh
#   2. BeforeInstall      <- YOU ARE HERE
#   3. Install            CodeDeploy copies the .war
#   4. ApplicationStart   start_server.sh
#
# Two jobs:
#   1. Install the software needed to serve the app (Tomcat and Apache httpd)
#   2. Write the Apache reverse proxy configuration
#
# Runs as root (set by appspec.yml), which it needs for both installing
# packages and writing into /etc/httpd/.
#
# NOTE: this runs on EVERY deployment, reinstalling packages that are almost
# always already present. Harmless (yum skips what is already installed) but
# wasteful - it really belongs in a one-time instance bootstrap or a custom AMI.
# ============================================================================

# --- Install Tomcat: the Java servlet container -----------------------------
# This is what actually runs the .war file. It listens on port 8080 and serves
# the app at http://localhost:8080/nextwork-web-project/
#   -y   answer "yes" automatically. ESSENTIAL - there is no human present to
#        respond to a prompt, and a script waiting on input would hang until
#        the 300 second timeout in appspec.yml killed the deployment.
sudo yum install tomcat -y

# --- Install Apache httpd: the public facing web server ---------------------
# Listens on port 80 and forwards requests to Tomcat. See the proxy config
# below for why this second server is worth having at all.
sudo yum -y install httpd

# ============================================================================
# WRITE THE APACHE REVERSE PROXY CONFIG
#
# WHY A REVERSE PROXY AT ALL:
# Tomcat serves the app at  localhost:8080/nextwork-web-project/  which is an
# awkward URL on a non-standard port. Nobody wants to type a port number. So
# Apache sits on port 80 (the default for http://, so it is invisible in the
# address bar) and quietly forwards everything to Tomcat. Visitors reach the
# app at the plain domain root. It also means Tomcat never has to be exposed
# to the internet directly.
#
# HOW THIS WRITES THE FILE:
#   cat << EOF > somefile   is a "heredoc". Everything between this line and
#   the closing EOF is written into the file, replacing its contents. Anything
#   dropped into /etc/httpd/conf.d/ is picked up by Apache automatically.
#
# SUBTLETY WORTH KNOWING: in "sudo cat << EOF > file", the sudo applies to cat
# but NOT to the > redirect, which the shell performs as the current user. It
# works here only because appspec.yml already runs this whole script as root.
# The more robust form would be:  sudo tee /etc/httpd/conf.d/... > /dev/null
# ============================================================================
sudo cat << EOF > /etc/httpd/conf.d/tomcat_manager.conf
# Handle requests arriving on port 80 (the standard, invisible HTTP port).
<VirtualHost *:80>
  # Where Apache sends server problem notifications.
  ServerAdmin root@localhost

  # The hostname this virtual host answers for.
  ServerName app.nextwork.com

  # Assume plain HTML when a file's type cannot be determined.
  DefaultType text/html

  # Do NOT act as a forward proxy. Off is important for security: leaving it
  # on would let strangers route arbitrary internet traffic through this
  # server. We only want the REVERSE proxy behaviour configured below.
  ProxyRequests off

  # Pass the visitor's original Host header through to Tomcat, rather than
  # rewriting it to localhost. Without this, any link Tomcat generates would
  # point at localhost and break for real visitors.
  ProxyPreserveHost On

  # THE FORWARDING RULE. Everything arriving at the site root gets handed to
  # Tomcat's app on port 8080. This is the line that joins the two servers.
  ProxyPass / http://localhost:8080/nextwork-web-project/

  # THE RETURN RULE. Rewrites headers on the way BACK OUT, so redirects Tomcat
  # issues point at the public address instead of leaking localhost:8080 into
  # the visitor's browser. ProxyPass alone handles requests in; this handles
  # responses out. You need both.
  ProxyPassReverse / http://localhost:8080/nextwork-web-project/
</VirtualHost>
EOF
# ^ This EOF must sit alone at the start of a line with no indentation, or the
#   heredoc never terminates and the script breaks.
