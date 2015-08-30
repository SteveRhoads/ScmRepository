# Copyright 2002-2012 Rally Software Development Corp. All Rights Reserved.

require 'time'
require 'rally_proxy'
require 'msgripper'

RALLY_VERSION = "v2.0" #1.27

class SCMConnector

  attr_reader :fields, :prefix, :states, :state_field, :user_domain
  attr_reader :logger
  attr_accessor :changeset_number, :artifacts

  # The commit message used to make a discussion object in Rally
  # Ex: "DE123 Fixed I fixed the error in this code"
  @commit_message = ""

  # An array of file names that were changed and noted during this commit
  # Ex: ["A /File1.java","A File2.cs"]
  @affected_files = []

  # The person who made the change in the scm
  # Ex: "aUser"
  @committer = nil

  include CommitMessageExaminer

  def initialize(config)
    @config       = config
    @workspace    = config.workspace_name
    @logger       = config.logger
    @prefix       = config.prefix
    @user_domain  = config.user_domain
    @artifacts    = []
    @state_field  = { :defect                   => 'State',
                      :task                     => 'State',
                      :hierarchical_requirement => 'ScheduleState',
                      :defect_suite             => 'ScheduleState'
                    }
    @rally = RallyProxy.new(@logger)
  end

  def connect_to_rally(base_url, workspace_name, username, password, version=RALLY_VERSION)
    @logger.debug("scm_connector.connect_to_rally")
    #Setup header information
    custom_headers         = RallyAPI::CustomHttpHeader.new()
    custom_headers.name    = 'Rally Connector for ' + get_connector_name()
    custom_headers.version = get_connector_version()
    custom_headers.vendor  = 'Rally Software'

    @rally.connect(base_url, workspace_name, username, password, custom_headers, version)
    @states = @rally.get_states()
  end

  # PSEUDO VIRTUAL FUNCTIONS SECTION

  # Pseudo Virtual Function: MUST be overridden
  # The commit message used to make a changeset and associated changes in Rally
  # Ex: "DE123 Fixed I fixed the error in this code"
  def get_commit_message()
    @logger.error("scm_connector.get_commit_message# You need to override the get_commit_message() method")
    raise(RuntimeError, "You need to override the get_commit_message() method")
  end

  # Pseudo Virtual Function: MUST be overridden
  # An array of affected files
  # Example:
  # ['A /trunk/text1.html', 'A /trunk/text1.html']
  def get_affected_files()
    @logger.error("scm_connector.get_affected_files# You need to override the get_affected_files() method")
    raise(RuntimeError, "You need to override the get_affected_files() method")
  end

  # Pseudo Virtual Function: MUST be overridden
  # Build change object for Rally. Fields include action, path_and_filename, base, extension and u_r_i (all optional)
  # Example:
  # {"Action" => "A", "PathAndFilename" => "/trunk/text1.html", "Base" => "text1", 
  #  "Extension" => "html", "Uri" => "localhost:8080/trunk/text1.html"
  # }
  def construct_change_object(file)
    @logger.error("scm_connector.construct_change_object# You need to override the construct_change_object() method")
    raise(RuntimeError, "You need to override the construct_change_object() method")
  end

  # Pseudo Virtual Function: MUST be overridden
  # The person who made the change in the scm
  # Ex: "aUser"
  def get_committer()
    @logger.error("scm_connector.get_committer# You need to override the get_committer() method")
    raise(RuntimeError, "You need to override the get_committer() method")
  end

  # Used for SCMRepository type
  def get_connector_name()
    @logger.warn("scm_connector.get_connector_name# You should override the get_connector_name() method")
    return "SCM"
  end

  def get_connector_version()
    @logger.warn("scm_connector.get_connector_version# You should override the get_connector_version() method")
    return "3.7"
  end

  def execute(changeset_num)
    # intended entry point method - gathers information from the commit message
    # including artifact identifiers (FormattedIDs) and state transition directives
    # like (Fixed, Completed, Closed, etc.).
    # If an artifact identifier is detected and validated as existing in the configured
    # workspace in Rally, the artifact will be associated with the Changesets constructed
    # controlled by this method.  Change records will be created for each file in the Changeset.
    # Finally if valid state transition directives can be associated to one or more 
    # Rally artifact identifiers (by direct proximity either before or after the identifier(s))
    # then those specific artifacts will have their state updated to the specified state.

    @logger.debug("scm_connector.execute examining changeset_num #{changeset_num}")

    @changeset_number = changeset_num
    @commit_message   = get_commit_message()
    @affected_files   = get_affected_files()
    @committer        = get_committer()

    # get or create the SCMRepository in the configured Workspace
    @workspace = @config.workspace_name
    @scmrepository = get_rally_scmrepository(@config.scmrepository_name)

    @artifacts = identify_valid_artifacts(@commit_message)

    # create the Changeset and associate all the valid reference Rally artifacts
    @logger.info("Creating Rally changeset...")
    @rally_changeset = create_rally_changeset()

    # create a Change record for each file that was part of the changeset
    @logger.info("Creating Rally changes...")
    create_rally_changes()

    # now attempt to decipher what if any artifact state changes need to be executed
    #    legal: (as in they cause state transitions)
    #      State1 Artifact1 Artifact2 State2 Artifact3 Artifact4 ...
    #      Artifact1 Artifact2 State1 Artifact3 Artifact4 State2 ...
    #    all other offerings are rejected as far as attempting any artifact state updates
    actargs = extract_actions_and_targets(@commit_message)

    # effect the state transition on items that are eligible for that treatment
    trigger_state_transition(actargs)

    @logger.info("scm_connector.execute finished with changeset_num #{changeset_num}")
  end

  # For specific SCM connectors, this can be overriden to include URL links, etc.
  def format_committer(author)
    return author.strip
  end

  # For specific SCM connectors, this can be overriden to include URL links, etc.
  def format_commit_message(commit_message)
    return commit_message.strip
  end

  # Builds the URI based on the revision
  # This URI will be stored on the Rally changeset object
  # For specific SCM connectors, you should override this to create a true URL link
  def get_changeset_uri(revision)
    return revision
  end

  # Builds the URI based on the affected file
  # This URI will be stored on the Rally change object
  # For specific SCM connectors, you should override this to create a true URL link
  def get_change_uri(filepath)
    return filepath
  end

  def get_rally_scmrepository(name)
    scm_repo = @rally.find_by_value('SCMRepository', 'Name', name)
    return scm_repo unless scm_repo.nil?
    scm_repo = create_rally_scmrepository()
    return scm_repo
  end


  def create_rally_scmrepository()
    @logger.debug("scm_connector.create_rally_scmrepository# for #{@config.scmrepository_name}")

    fields = {}
    fields['Name']        = @config.scmrepository_name
    fields['Description'] = @config.scmrepository_name
    fields['SCMType']     = get_connector_name()
    fields['Uri']         = @config.scm_url or ""
    scm_repo = @rally.create_item('SCMRepository', fields)
    return scm_repo
  end

  def find_rally_user(committer_name)
    @logger.debug("committer to lookup - #{committer_name}")
    if @config.strip_committer_prefix != nil
      committer_name = committer_name.strip.split(@config.strip_committer_prefix)[1]
    end

    rally_user = nil
    if @config.committer_user_lookup_field != nil and committer_name != nil
      committer_string = committer_name.strip.downcase
      culf = @config.committer_user_lookup_field
      rally_user = @rally.find_by_value('User', culf, committer_string)
    end
    return rally_user if !rally_user.nil?

    if @config.user_domain != nil
      user_name = transform_to_rally_username(committer_name)
      return @rally.find_by_value('User', 'UserName', user_name)
    end
    return nil
  end

  def transform_to_rally_username(scm_user)
    @logger.debug("SCM Author - #{scm_user}")

    rally_username = scm_user.strip.downcase
    if @config.user_domain != nil
      rally_username = '%s@%s' % [rally_username, @config.user_domain]
    end

    return rally_username
  end

  def identify_valid_artifacts(message)
    # find all the artifacts mentioned in the commit message 
    # retain only those that are valid Rally artifacts in the configured workspace
    @logger.debug("scm_connector.identify_valid_artifact# message = \'#{message}\'")
    tokens = message.gsub(',', ' ').split(' ') # turn commas into spaces and split on spaces
    pfxs = @prefix.values.join('|')  # to get a string of DE|TA|US|...
    candidate_artifact_identifiers = tokens.select {|tok| tok =~ /^(#{pfxs})\d+$/ }
    @logger.debug("    candidate_artifact_identifiers = \'#{candidate_artifact_identifiers.inspect}\'")

    valid_artifacts = []
    xfp = @prefix.invert
    candidate_artifact_identifiers.each do |formatted_id| 
        art_pfx = formatted_id.gsub(/\d+/, '')
        @logger.debug("   art_pfx: |#{art_pfx}|")
        next if !xfp.key?(art_pfx)
        art_type = xfp[art_pfx]
        @logger.debug("   art_type: |#{art_type}|")
        artifact = @rally.find_artifact(art_type, formatted_id)
        if artifact
          @logger.debug("   artifact #{formatted_id} has ObjectID value of #{artifact.ObjectID}")
          valid_artifacts << artifact
        end
    end
    artifact_idents = valid_artifacts.collect {|art| art.FormattedID}
    @logger.debug("scm_connector.identify_valid_artifact# artifacts set to #{artifact_idents.inspect}")
    return valid_artifacts
  end

  def create_rally_changeset()
    @logger.debug("scm_connector.create_rally_changeset#")

    skinny_artifacts = []
    @artifacts.each do |art|
        skinny_artifacts <<  { '_type'       => art._type, 
                               '_ref'        => art._ref, 
                               'ObjectID'    => art.ObjectID,
                               'FormattedID' => art.FormattedID, 
                               'Name'        => art.Name 
                             }
    end

    fields = {}
    fields['SCMRepository']    = 'scmrepository/%s' % @scmrepository.ObjectID
    fields['Revision']         = @changeset_number
    fields['CommitTimestamp']  = Time.now.iso8601
    fields['Message']          = format_commit_message(@commit_message)[0..3999]
    fields['Uri']              = get_changeset_uri(@changeset_number)
    fields['Artifacts']        = skinny_artifacts
    fields['Author']           = find_rally_user(@committer) or '><--None--><'
    fields.delete('Author') if fields['Author'] == '><--None--><'

    @logger.debug("scm_connector.create_rally_changeset# with fields: #{fields.to_s}")
    changeset = @rally.create_item('Changeset', fields)
    @logger.debug("scm_connector.create_rally_changeset# return Changeset item with OID: #{changeset.ObjectID} Name: #{} #{changeset._refObjectName}")
    return changeset
  end

  def get_file_base(filepath)
    last_file = filepath.split(/\//).pop()
    base      = last_file[/(?:.*\.)/, 0]
    if base.nil?
      return last_file
    else
      return base.slice(0, base.length-1)
    end
  end

  def get_file_extension(filepath)
    extension = filepath[/(?:.*\.)(.*$)/, 1]
    extension = '' if extension.nil?
    return extension
  end

  def create_rally_changes()
    @logger.debug("scm_connector.create_rally_changes#")
    rally_changes = []

    changeset_ref = 'changeset/%s' % @rally_changeset.ObjectID
    @affected_files.each do |file|
      change_fields = { 'Changeset' => changeset_ref }
      change_fields.merge!(construct_change_object(file))
      change = @rally.create_item('Change', change_fields)
      rally_changes << change
    end
    return rally_changes
  end

  def trigger_state_transition(actargs)
    formatted_ids = @artifacts.collect {|art| art.FormattedID}
    pfxs = @prefix.values.join('|')  # to get a string of DE|TA|US|...
    actargs.each do |action_and_targets|
        action, targets = action_and_targets.each_pair.first
        next if action.nil? or targets.nil? or targets.length == 0
        valid_targets = targets.select {|target| formatted_ids.include?(target)}
        valid_targets.each do |art_id|
            pfx = $1 if art_id.upcase =~ /^(#{pfxs})\d+$/  # this should always have a non-nil result
            if pfx.nil?
                @logger.info("Skipping update of  #{art_id} state to #{action}, unknown artifact prefix")
                next
            end
            @logger.info("Updating #{art_id} state to #{action}...")
            type = @prefix.invert[pfx]
            update_fields = construct_artifact_fields(action, type, pfx)
            artifact = @artifacts.select {|art| art.FormattedID == art_id}.first
            result   = @rally.update_item(artifact, update_fields)
            @logger.info("Updated #{art_id} state to #{action} : #{result}")
        end
    end
  end

  def construct_artifact_fields(state, type, pfx)
    update_fields = { 'Changeset' => 'changeset/%s' % @rally_changeset.ObjectID }

    if state
      @logger.info("State found: #{state}")
      if (type == :task and @prefix[type] == pfx and state == "Completed")
        update_fields['ToDo'] = 0
      end
      update_fields[@state_field[type]] = state
    else
      @logger.info("State not found: #{state}")
    end

    return update_fields
  end

end
