#!/usr/bin/env ruby
# Copyright 2002-2012 Rally Software Development Corp. All Rights Reserved.

# Rally Connector for <VersionControlSystem_X_) configuration checker

dir = File.dirname(__FILE__)
app_path = File.expand_path("#{dir}/lib/")
unless $LOAD_PATH.include?(app_path)
  $LOAD_PATH.unshift app_path
end

$LOAD_PATH.unshift "."

require 'scm_config_reader'
require 'rally_api'

###################################################################################
#
# has to check for:
#
#    Ruby version must be 1.9.2 or better
#    rally_api gem must be installed and 0.4.1 or better
#    path the directory this script lives in should be searchable for 'other'  ie., r-xr-xr-x
#    RallyWrapper.sh          should be readable and executable by process owner
#    <vcs>2rally.rb           should be readable by the process owner
#    path to log file         must be writable by process owner (who is probably not owner/group member)
#    Rally URL check          server value one that is known?
#    Rally Connection check   credentials valid?
#    Rally Workspace check    does the Workspace specified in the config exist?
#    The Build and Changeset flag must be enabled
#    Email validation check
#
###################################################################################

@rally     = nil
@workspace = nil
@warnings  = 0
@logger    = "" # for the config.logger

CHECK_ITEM_FORMAT = "%-48.48s   %-8.8s"

GENERAL_WARNING_NOTE = %{
Several WARNING conditions were detected during this check.  These warning 
conditions are associated with directories and files not being "world" 
searchable or readable or executable.  If the post-commit process runs as 
the owner of the directory where the connector is installed and executed 
then you can safely disregard these warnings.  However, if the process that 
runs the post-commit hook (the UID) is not the same as the UID of the user
that owns the directory where the connector is installed, then you must 
rectify any WARNING condition noted above.
}

###################################################################################

def main()
  puts " 1. %s" % [check_ruby_version()]
  puts " 2. %s" % [check_rally_api_gem()]
  puts " 3. %s" % [check_directory_searchability(Dir.pwd)]
  # puts " 4. %s" % [check_wrapper_world_executability('RallyWrapper.sh')]
  # puts " 5. %s" % [check_vcs_connector_script_world_readability()]
  puts " 6. %s" % [check_log_write()]
  puts " 7. %s" % [check_rally_url(@config)]
  puts " 8. %s" % [check_can_connect(@config)]
  puts " 9. %s" % [check_valid_workspace(@config)]
  puts "10. %s" % [check_build_and_changeset_enabled(@config)]
  # puts "11. %s" % [check_valid_email(@config.user_name)]

  #sr
  puts "11. %s" % [listSCMRepositories(@workspace)]
  #puts "12. %s" % [getSCMRepository(@workspace, "STEMRobotics")]
  #puts "13. %s" % [getSCMRepository(@workspace, "hspd_svn")]
  puts "14. %s" % [create_rally_scmrepository()]

  #puts "15. %s" % [delete_rally_scmrepository(@workspace,"hspd_svn")]
  puts "16. %s" % [listSCMRepositories(@workspace)]

=begin
  if @warnings > 0
    puts GENERAL_WARNING_NOTE
  end
=end
end

###################################################################################

def check_ruby_version()
  check_name = "Ruby version check"
  if RUBY_VERSION[0..3] != "1.9" and RUBY_VERSION[-1].to_i < 2
    problem = "Ruby version must be 1.9.2 or greater (yours is #{RUBY_VERSION})"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   --  #{problem}")
  end

  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_rally_api_gem()
  check_name = "Ruby rally_api gem check"
  result = %x[gem list rally_api]
  if result.length < 1
    problem = "no rally_api found"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
  end
  result.chop!
  if result =~ /rally_api \((\d\.\d\.\d+)\)/
    gem_version = $1
  else
    problem = "gem list rally_api result string in unexpected format: |#{result}|"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
  end
  major, minor, point = gem_version.split('.').map {|level| level.to_i}
  if major == 0
    if minor < 4
      problem = "rally_api version insufficient: |#{gem_version}|"
      return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
    else  
      if point < 1
        problem = "rally_api version insufficient: |#{gem_version}|"
        return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
      end
    end
  end

  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_directory_searchability(path)
  check_name = "Current directory world searchability check"

  path_components = path.to_s.split('/').select {|comp| comp and comp.length > 0}
  directory_path = ''
  path_components.each_with_index do |component, ix|
    prepend = '/'
    prepend = '' if ix == 0 and component.count(':') > 0  # which will happen on Windows
    directory_path += (prepend + path_components.shift)
    mode = File::Stat.new(directory_path).mode
    if (mode % 2) == 0
      @warnings += 1
      problem = "this directory is not searchable for non user/group process owner"
      return (CHECK_ITEM_FORMAT % [check_name, "WARNING"] + "  --  #{problem}")
     end
  end

  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_wrapper_world_executability(wrapper)
  check_name = "Wrapper script world executability check"
  full_path = File.join(Dir.pwd, wrapper)
  if !File::file?(full_path)
    problem = "wrapper script not present or not a file"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
  end
  temp = "%o" % File::Stat.new(full_path).mode
  world = temp[-1].to_i
  executable = (world % 2 > 0)
  if !executable
    @warnings += 1
    problem = "wrapper script %s not world executable" % wrapper
    return (CHECK_ITEM_FORMAT % [check_name, "WARNING"] + "  --  #{problem}")
  end

  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_vcs_connector_script_world_readability()
  check_name = "<vcs>2rally.rb driver world readability check"
  matches = Dir.glob('*2rally.rb')
  if matches.length == 0
    problem = "<vcs>2rally.rb script not present"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
  end
  # TODO: what if matches has more than 1 item?
  driver = matches.first
  full_path = File.join(Dir.pwd, driver)
  if !File::file?(full_path)
    problem = "%s script not present or not a file" % driver
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "  --  #{problem}")
  end
  temp = "%o" % File::Stat.new(full_path).mode
  world = temp[-1].to_i
  readable = (world & 4 > 0)
  if !readable
    @warnings += 1
    problem = "driver script %s not world readable" % driver
    return (CHECK_ITEM_FORMAT % [check_name, "WARNING"] + "  --  #{problem}")
  end
  
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################
  
def check_log_write
  check_name = "Log file write check"

  #TEST# puts File.dirname(__FILE__) + "/config.xml"

  begin 
    @config = ScmConfigReader.new()
    @config.read_xml_config(File.dirname(__FILE__) + "/config.xml")
  rescue Exception => ex
    problem = "Unable to find/read config.xml file"
    puts " 5. Log file write check            FAILED   --  #{problem}"
    Process.exit
  end

  begin
    @logger = @config.logger
    @logger.level = 0
  rescue Errno::EACCES
    problem = "Unable to write/open to log file (Rally_Connector_Error.log)"
    puts " 5. Log file write check            FAILED   --  #{problem}"
    Process.exit
  end
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_rally_url(config)
  check_name = "Rally Url check"
  valid_url = false

  case config.rally_base_url
    when "https://test1cluster.rallydev.com/slm"
      valid_url = true
    when "https://rally1.rallydev.com/slm"
      valid_url = true
    when "https://sandbox.rallydev.com/slm"
      valid_url = true
    when "https://trial.rallydev.com/slm"
      valid_url = true
    when "https://preview.rallydev.com/slm"
      valid_url = true
    when "https://demo.rallydev.com/slm"
      valid_url = true
    when "https://demo2.rallydev.com/slm"
      valid_url = true
  end
  if !valid_url
    problem = "Server appears to be outside of Rally. Do you have an on-premise installation?"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   --  #{problem}")
  end
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_can_connect(config)
  check_name = "Rally Connection check"
  custom_headers = RallyAPI::CustomHttpHeader.new()
  custom_headers.name    = 'Rally SCM Config Checker'
  custom_headers.version = "2.0"
  custom_headers.vendor  = 'Rally Software'
  rally_config = { :base_url  => config.rally_base_url,
                   :username  => config.user_name,
                   :password  => config.password,
                   :workspace => config.workspace_name,
                   :headers   => custom_headers,
                   :version   => 'v2.0'
                 }
  begin
    @rally = RallyAPI::RallyRestJson.new(rally_config)
  rescue Exception => ex
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- #{ex.to_s}")
  end

  if @rally.nil?
    return CHECK_ITEM_FORMAT % [check_name, "FAILED"]
  end
  
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_valid_workspace(config)
  check_name = "Rally Workspace check"
  @workspace = nil
  begin
    @workspace = @rally.find_workspace(config.workspace_name)
  rescue Exception => ex
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- #{ex.to_s}")
    return "Rally Workspace Error - " + e.to_s
  end

  if @workspace.nil?
    condition = "No Open Rally workspace named #{config.workspace_name} found. "
    note      =  'Note: Workspace names are case sensitive.'
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- #{condition} #{note}")
  else
    @workspace.read()
  end
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_build_and_changeset_enabled(config)
  check_name = "Rally Build and Changeset flag enabled check"
  if @workspace.nil?
    condition = "Specified Workspace invalid or non-existent"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- #{condition}")
  end

  wksp_conf = @workspace.WorkspaceConfiguration
  wksp_conf.read()

  if wksp_conf.BuildandChangesetEnabled != true
    condition = "Build and Changeset flag not enabled for your workspace"
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- #{condition}")
  end

  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

###################################################################################

def check_valid_email(email)
  check_name = "Email validation check"
  unless email =~ /^[a-zA-Z][\w\.-]*[a-zA-Z0-9]@[a-zA-Z0-9][\w\.-]*[a-zA-Z0-9]\.[a-zA-Z][a-zA-Z\.]*[a-zA-Z]$/
    return (CHECK_ITEM_FORMAT % [check_name, "FAILED"] + "   -- Username is not a valid email address")
  end
  return CHECK_ITEM_FORMAT % [check_name, "PASSED"]
end

#sr 2015-08-30
def getSCMRepository(workspace, repo_name)
  query = RallyAPI::RallyQuery.new(:type      => :scmrepository,
                                   :fetch     => true,
                                   :workspace => @wksp)
  query.query_string = '(Name = "%s")' % repo_name
  # puts "QueryString=#{repo_name}"

  begin
    results = @rally.find(query)
  rescue Exception => ex
    problem = "Unable to obtain Rally query results for SCMRepository named '%s'" % ex.message
    #sr boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
    #sr raise boomex, problem
    puts "\t\tProblem: #{problem}"
    @logger.debug problem

  end
  if results.length > 0
    return results.first
  else
    @logger.debug("No SCMRepository named |#{repo_name}| in Workspace: |#{workspace.Name}|")
    return nil
  end
end

#sr 2015-08-30
def get_rally_scmrepository(name)
  scm_repo = @rally.find_by_value('SCMRepository', 'Name', name)
  return scm_repo unless scm_repo.nil?
  scm_repo = create_rally_scmrepository()
  return scm_repo
end

#sr 2015-08-30
def create_rally_scmrepository()
  @logger.debug("scm_connector.create_rally_scmrepository# for #{@config.scmrepository_name}")

  fields = {}
  fields['Name']        = @config.scmrepository_name
  fields['Description'] = @config.scmrepository_name
  fields['SCMType']     = "SCM" #SR get_connector_name()
  fields['Uri']         = @config.scm_url or ""
  scm_repo = @rally.create(:scmrepository, fields)
  return scm_repo
end

#sr 2015-08-30
def delete_rally_scmrepository(workspace, scmrepository)
  @logger.debug("scm_connector delete_rally_scmrepository# for #{@config.scmrepository_name}")

  scmrepo_ref = getSCMRepository(workspace, scmrepository)

  scmrepo_ref.delete

end

#sr 2015-08-30
def listSCMRepositories(workspace)
  query = RallyAPI::RallyQuery.new(:type      => :scmrepository,
                                   :fetch     => true,
                                   :workspace => @wksp)
  #query.query_string = '(Name = "%s")' % repo_name
  begin
    results = @rally.find(query)
  rescue Exception => ex
    problem = "Unable to obtain Rally query results for SCMRepository named '%s'" % ex.message
    boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
    raise boomex, problem
  end
  if results.length > 0
    return_str = "List of existing SCM Repositories in Workspace:(#{@workspace.Name})"
    results.each_with_index { |r, i |
      return_str = return_str + "\n\t\tSCM Repo(#{i}) #{r}"
    }
    return return_str
    # return results.first
  else
    @logger.debug("No SCMRepository named |#{repo_name}| in Workspace: |#{workspace.Name}|")
    return nil
  end
end

###################################################################################
###################################################################################

main()

