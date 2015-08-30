# Copyright 2002-2012 Rally Software Development Corp. All Rights Reserved.

require 'fileutils'
require 'logger'
require 'rexml/document'

require 'obfuscate'

ERROR_LOG_NAME = 'Rally_Connector_Error.log'

class ScmConfigReader
  attr_accessor :user_name, :password, :rally_base_url, :workspace_name, :scm_url
  attr_accessor :logger, :log_file_name, :scmrepository_name, :user_domain
  attr_accessor :prefix, :strip_committer_prefix, :committer_user_lookup_field
  attr_reader   :encoded_password

  def read_xml_config(xml_config_filename)

    @xml_config_filename = xml_config_filename
    if !File.readable_real?(@xml_config_filename)
      raise "Xml Config File: #{@xml_config_filename} Not Readable"
    end

    file = File.new(@xml_config_filename)
    @doc = REXML::Document.new(file)
    @root = @doc.root
    file.close()

    get_log_info()
    @logger.info("Rally Connector triggered...")
    @logger.debug("Entering read_xml_config_file")

    get_rally_server_info()
    @logger.debug("RallyBaseUrl: #{@rally_base_url}")

    get_rally_credentials_info()
    @logger.debug("RallyUsername: #{@user_name}")

    get_rally_workspace_info()
    @logger.debug("RallyWorkspaceName: #{@workspace_name}")

    get_rally_repository_info()
    @logger.debug("RallySCMRepositoryName: #{@scmrepository_name}")

    get_rally_committer_mapping_info()
    @logger.debug("UserDomain: #{@user_domain}")
    @logger.debug("Rally User field for SCM User: #{@committer_user_lookup_field}")
    @logger.debug("Stripping this prefix of committers: #{@strip_committer_prefix}")

    get_rally_artifact_prefix_info()

    get_vcs_url_info()
    @logger.debug("SourceControlUrl: #{@scm_url}")

    # do we need to rewrite the config file with a newly encoded password?
    rewrite(@doc, @xml_config_filename) if @encoded_password  
        
    # rewrite the config without any of the CachedStates info (which was in pre 3.7 versions)
    cleanup(@xml_config_filename) if @root.elements["CachedStates"]

    @logger.debug("Leaving read_xml_config")
  end

  def get_log_info()
    #default the log file name
    #override with user specified log file name if given
    #open the log file
    #set the log level to the default value
    #override with user specified log level if given

    conf_log_file_name = ERROR_LOG_NAME
    if @root.elements["Log"]
      conf_log_file_name = File.basename(@root.elements["Log"].elements["FileName"].text.strip)
    end
    @log_file_name = '%s/../%s' % [File.dirname(__FILE__), conf_log_file_name]
    @logger = Logger.new(log_file_name, shift_age = 'weekly')
    @logger.level = Logger::ERROR
    if @root.elements["Log"]
      @logger.level = Logger::WARN
      if @root.elements["Log"].elements["Level"]
        @logger.level = @root.elements["Log"].elements["Level"].text.strip.to_i
      end
    end
  end

  def get_rally_server_info()
    # Valid URL for production is: https://rally1.rallydev.com/slm (NO slash after slm)
    # Valid URL for trial      is: https://trial.rallydev.com/slm
    @rally_base_url = "https://" + @root.elements["RallyBaseUrl"].text.strip
    @rally_base_url.chop! if @rally_base_url[-1] == '/'
    if !@rally_base_url[@rally_base_url.length-4, @rally_base_url.length] != "/slm"
      @rally_base_url += "/slm"
    end
  end

  def get_rally_credentials_info()
    @encoded_password = false  # assume the password is not yet in the encoded form

    @user_name = @root.elements["RallyUserName"].text.strip
    @password  = @root.elements["RallyPassword"].text.strip
    if !Obfuscate.encoded? @password
      @root.elements["RallyPassword"].text = Obfuscate.encode(@password)
      @encoded_password = true
    else
      @password = Obfuscate.decode(@password)
    end
  end

  def get_rally_workspace_info()
    # should probably squawk about not having a RallyWorkspaceName element
    @workspace_name = @root.elements["RallyWorkspaceName"].text.strip
  end

  def get_rally_repository_info()
    # should probably squawk about not having a RallySCMRepositoryName element
    @scmrepository_name = @root.elements["RallySCMRepositoryName"].text.strip
  end

  def get_rally_committer_mapping_info()
    @user_domain = nil
    if @root.elements["UserDomain"]
      if @root.elements["UserDomain"].text.strip.length > 0 
        @user_domain = @root.elements["UserDomain"].text.strip
      end
    end

    @committer_user_lookup_field = nil
    if @root.elements["CommitterUserLookupField"]
      if @root.elements["CommitterUserLookupField"].text.strip.length > 0
        @committer_user_lookup_field = @root.elements["CommitterUserLookupField"].text.strip
      end
    end

    @strip_committer_prefix = nil
    if @root.elements["StripCommitterPrefix"]
      if @root.elements["StripCommitterPrefix"].text.strip.length > 0
        @strip_committer_prefix = @root.elements["StripCommitterPrefix"].text.strip
      end
    end
  end

  def get_rally_artifact_prefix_info()
    # Artifact prefix assignments
    pfx = @root.elements["Prefixes"].elements
    @prefix = { :defect       => pfx["Defect"].text.strip,
                :defect_suite => 'DS',  # yeh, this is arbitrary...
                :task         => pfx["Task"].text.strip,
                :hierarchical_requirement => pfx["Story"].text.strip
              }
  end

  def get_vcs_url_info()
    # This is the base URL for your SCM server
    # Set to nil if you don't want to create URIs for changeset and change objects
    @scm_url = nil
    return if !@root.elements["SourceControlUrl"]

    temp = @root.elements["SourceControlUrl"].text.strip
    return if temp.length == 0

    @scm_url = temp
    if @scm_url !~ /^\w+\+?\w+:\/\//   # doesn't start with a protocol spec (http://, https://, svn+ssh://, etc)?
      @scm_url = "http://" + @scm_url  # provide the default protocol
    end
  end

  def cleanup(target_file)
    cf = File.open(target_file, "r")
    conf = cf.read()
    cf.close()
    conf.gsub!(/<CachedStates>.+<\/CachedStates>/m, '')
    xml_doc = REXML::Document.new(conf)
    rewrite(xml_doc, target_file)
  end

  def rewrite(xml_doc, dest_file)
    if !File.writable_real?(dest_file)
      raise "Xml Config File: #{dest_file} Not Writable"
    end
    xcf = File.open(dest_file, "w")
    begin
      formatter = REXML::Formatters::Pretty.new(indentation=4)
    rescue Exception => ex
      puts "REXML Formatters problem, #{ex.to_s}"
      raise
    end
    formatter.compact = true
    formatter.width   = 80
    prettified = formatter.write(xml_doc.root, "")
    xcf.write(prettified + "\n")
    xcf.close()
    @logger.debug("Rewrote config file")
  end

end
