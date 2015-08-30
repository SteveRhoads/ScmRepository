# Copyright 2002-2012 Rally Software Development Corp. All Rights Reserved.

require 'rally_api'

RALLY_WSAPI_VERSION = 'v2.0'

class RallyProxy

  attr_accessor :rally
  attr_accessor :workspace

  def initialize(logger=nil)
    @rally     = nil
    @workspace = nil
    @username  = nil
    if !logger
      @logger = Logger.new('RallyProxy.log')
      @logger.level = Logger::WARN
    else
      @logger = logger
    end
  end

  def connect(base_url, workspace_name, username, password, custom_headers, version=RALLY_WSAPI_VERSION)
    @username = username
    # Make sure the last character of the URL is not a /
    base_url.chop! if base_url[-1] == '/'
    config = {:base_url  => base_url,
              :username  => username,
              :password  => password,
              :workspace => workspace_name,
              :headers   => custom_headers,
              :version   => version
             }
    begin
      #login to Rally
      @rally = RallyAPI::RallyRestJson.new(config)
      @logger.info("Successfully connected to Rally")
    rescue Exception => ex
      raise("\nERROR: Could not connect to Rally! Error returned was: #{ex.message}")
    end

    @workspace = @rally.rally_default_workspace
    @workspace.read()
    check_build_flag_enabled()

    return true
  end

  def create_item(type, fields)
    @logger.debug("rally_proxy.create_item #{type}")
    fields['Workspace'] = 'workspace/%s' % @workspace.ObjectID unless fields.has_key?('Workspace')
    begin
      obj = @rally.create(type.to_s.downcase.to_sym, fields)
    rescue Exception => ex
      raise("Unable to create item #{type}: #{ex.message}")
    end
    return obj
  end

  def update_item(artifact, fields)
    @logger.debug("rally_proxy.update_item #artifact #{artifact} ")
    begin
      value =  artifact.update(fields)
    rescue Exception => ex
      raise "Unable to update artifact #{artifact.FormattedID} - Exception was: #{ex.message}"
    end
    @logger.debug("rally_proxy.update_item# returns #{value}")
    return value
  end

  def check_build_flag_enabled()
    @workspace.read()
    wksp_conf = @workspace.WorkspaceConfiguration
    wksp_conf.read()

    if (wksp_conf.BuildandChangesetEnabled == true)
      return true
    else
      @logger.warn('Build and changeset flag not enabled for your workspace!')
      @logger.warn('Most build and changeset data will not show in Rally until a workspace administrator enables this flag by editing the workspace.')
      return false
    end
  end

#  def find_workspace(workspace_name)
#    #
#    # Given a workspace name, plumb the "connected" user's subscription for workspaces 
#    # available for their credentials.
#    # If there is a workspace available matching the workspace_name,
#    # return back the JSON representation of the targeted Workspace 
#    #
#    workspace = nil
#    @logger.debug("rally_proxy.find_workspace#workspace_name #{workspace_name}")
#    begin
#      workspace = @rally.find_workspace(workspace_name)
#    rescue Exception => ex
#      @logger.error("Unable to find Workspace #{workspace_name}, #{ex}")
#      raise("\nERROR: Couldn't connect to Rally. Check baseurl, password and username in config file\n")
#    end
#
#    if workspace.nil?
#      raise "\nERROR: Couldn't find an open Rally workspace named '#{workspace_name}'\n"
#    end
#    workspace.read()
#    @logger.info("Workspace found: #{workspace}")
#    return workspace
#  end

  def get_allowed_values(type, attribute)
    # throw a space before the first cap letter of type beyond the initial char
    # eg., DefectSuite --> 'Defect Suite' 
    type = type.sub(/([a-z])([A-Z])/, '\1 \2')
    type = 'Hierarchical Requirement' if ['User Story', 'Story'].include?(type)
    item = find_by_value(:typedefinition, 'Name', type)
    return ['Completed'] if item.nil?
    targattr = item.Attributes.select {|attr| attr['ElementName'] == attribute}.first
    values = targattr['AllowedValues'].collect {|av| av.StringValue}
    return values
  end


  def get_states()
    @logger.debug("rally_proxy.get_states#")
    task_states         = ['Defined', 'In-Progress', 'Completed']  # this never changes...
    defect_states       = get_allowed_values('Defect', 'State')
    defect_suite_states = get_allowed_values('DefectSuite', 'ScheduleState')
    story_states        = get_allowed_values('UserStory',   'ScheduleState')
    art_states = {:defect       => defect_states, 
                  :defect_suite => defect_suite_states,
                  :task         => task_states, 
                  :story        => story_states,
                  :user_story   => story_states,
                  :hierarchical_requirement => story_states 
                 }
    @logger.debug("rally_proxy.get_states# returns #{art_states}")
    return art_states
  end

  def find_by_value(type, field, value)
    type_sym = type.downcase.to_sym
    query = RallyAPI::RallyQuery.new(:type => type_sym, :fetch => true, :workspace => @workspace)
    query.query_string = '(%s = "%s")' % [field, value]

    @logger.debug("rally_proxy.find_by_value# Type: #{type} Field: #{field} Value: #{value}")
    begin
      results = @rally.find(query)

      if results and results.first
        return results.first
      else
        return nil
      end
    rescue Exception => ex
      @logger.error("Unable to find #{type} item with #{field} == #{value}, #{ex}")
      raise ex
    end
  end

  def find_artifact(type, formatted_id)
    @logger.debug("rally_proxy.find_artifact# Type: #{type}, FormattedID: #{formatted_id})")
    query = RallyAPI::RallyQuery.new(:type  => type.to_s.downcase.gsub('_', '').to_sym, 
                                     :fetch => true, :workspace => @workspace)
    query.query_string = '(FormattedID = %s)' % [formatted_id]
    begin
      results = @rally.find(query)

      if results and results.first
        return results.first
      else
        return nil
      end
    rescue Exception => ex
      @logger.error("Unable to find #{type} #{formatted_id}, #{ex}")
      raise ex
    end
  end

end
