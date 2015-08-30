#!/bin/sh

RUBY_HOME="/usr/local/rvm/rubies/ruby-1.9.2-p290"
RUBY="${RUBY_HOME}/bin/ruby"
#export GEM_HOME=${RUBY_HOME}
VCS="svn"
VCS_TO_RALLY_DIR="/usr/local/integrations/VCS_ToRally"
CONNECTOR_DRIVER="${VCS_TO_RALLY_DIR}/${VCS}2rally.rb"

${RUBY} ${CONNECTOR_DRIVER} $1 $2
exit 0

