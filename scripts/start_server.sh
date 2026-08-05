#!/bin/bash
# ============================================================================
# start_server.sh  -  CODEDEPLOY HOOK: ApplicationStart
#
# RUNS LAST in the deployment lifecycle:
#   1. ApplicationStop    stop_server.sh
#   2. BeforeInstall      install_dependencies.sh
#   3. Install            CodeDeploy copies the .war into Tomcat's webapps/
#   4. ApplicationStart   <- YOU ARE HERE
#
# By the time this runs, the new .war is already sitting in
# /usr/share/tomcat/webapps/. Starting Tomcat is what makes it go live:
# Tomcat scans that folder on startup, unpacks the .war, and begins serving it.
#
# This is the final step of the whole pipeline. When this finishes successfully
# the code you pushed to GitHub is live on the internet.
#
# start vs enable - both are used below, and they do different things:
#   start   run the service NOW, in this boot session
#   enable  run the service automatically on EVERY future boot
# Using start alone would mean the site silently stays down after any instance
# reboot, until someone logs in and starts it by hand.
# ============================================================================

# --- Tomcat: the Java servlet container (port 8080) -------------------------
# Started FIRST, on purpose. Apache proxies traffic to Tomcat, so Tomcat should
# be coming up before Apache begins accepting public requests - otherwise the
# first visitors could hit a 502 Bad Gateway.
sudo systemctl start tomcat.service
sudo systemctl enable tomcat.service

# --- Apache httpd: the public facing web server (port 80) -------------------
# Started second. This is what actually opens the site to the outside world,
# forwarding requests to Tomcat using the proxy config that
# install_dependencies.sh wrote to /etc/httpd/conf.d/tomcat_manager.conf
sudo systemctl start httpd.service
sudo systemctl enable httpd.service

# If either service fails to start, systemctl returns non-zero, this hook
# fails, and CodeDeploy rolls the whole deployment back to the last working
# revision. That is the safety net - a deploy that cannot serve traffic never
# stays live.
