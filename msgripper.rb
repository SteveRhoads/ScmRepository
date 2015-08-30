
module CommitMessageExaminer

    POSSIBLE_ARTIFACT_RGX = Regexp.new('^([A-Za-z][A-Za-z]?)\d+$')

    def extract_actions_and_targets(message)
        # instance variables from the SCM_Connector instance we use:
        # @prefix - a hash keyed by artifact prefix with   a value of the artifact type
        # @status - a hash keyed by artifact prefix with the value a list of valid artifact states

        action = nil
        target = nil
        action_targets = []   # keyed by a valid State name (an action) with value 1 or more Artifacts (the FormattedID values)
        valid_prefixes = @prefix.values  
        all_actions    = []

        # stuff all_actions so that it has a complete and non-duplicated list of
        # all actions from each of the artifact types, and then create a hash
        # called action_capitalized keyed by valid_action.upcase with the value being the actual valid_action
        @states.each_pair do |key, value_list|
            value_list.each { |item| all_actions << item unless all_actions.include?(item)}
        end
        all_actions.sort!   # not strictly necessary but helps with debugging
        action_capitalized = {}  # key is action word capitalized for comparison, value is actual action value, ie., 'Completed'
        all_actions.each {|action| action_capitalized[action.upcase] = action}

        message = message.gsub(/\\n/, " -|- ")            # convert newline to a non-target and non-action token
        words = message.gsub(/(\.|,|;)/, ' ').split(' ')  # convert period, comma and semi-colon to space

        def valid_targets_for_action(action, target)
            valid_targets = []
            target.each do |item|
              item =~ /^([a-zA-Z][a-zA-Z]?)\d+$/ and pfx = $1
              art_sym    = @prefix.invert[pfx.upcase]
              art_states = @states[art_sym]
              valid_targets << item if art_states.include?(action)
            end
            return valid_targets
        end

        while words.length() > 0
            word = words.shift
            is_action = action_capitalized.has_key?(word.upcase)
            if is_action
                word = action_capitalized[word.upcase]
            end
            match = POSSIBLE_ARTIFACT_RGX.match(word) or false
            if match
              pfx = $1 
              is_target = valid_prefixes.include?(pfx.upcase) ? true : false
            else
              is_target = false
            end

            if !is_action and !is_target
                # store off whatever's in action and target in action_targets
                if action != nil and target != nil
                    # but only for the items in target for whom the action is valid
                    valid_targets = valid_targets_for_action(action, target)
                    action_targets << {action => valid_targets} if valid_targets.length > 0
                end
                action = nil
                target = nil
                next
            end

            if is_target
                target = [] if target.nil?   # turn it into a container for targets 
                                             # (the artifact FormattedID values)
                target << word.upcase
                next
            end

            # if we're here then is_action is true
            if word != action  # incoming is a _different_ action, 
                               # finish up the prior action
                if target != nil
                    ath = nil   # ath <-- shorthand for action target hash
                    if action != nil
                        # but we haven't yet determined whether the action is valid for the target(s)
                        valid_targets = valid_targets_for_action(action, target)
                        ath = {action => valid_targets} if valid_targets.length > 0 
                    else
                        ath = {word   => target}
                        word = nil  # we just consumed it...
                    end
                    action_targets << ath unless ath.nil?
                end
                target = nil
            end
            action = word
        end

        # deal with any leftovers after the end of the word stream
        if action != nil and target != nil
            valid_targets = valid_targets_for_action(action, target)
            action_targets << {action => valid_targets} if valid_targets.length > 0
        end

        return action_targets
    end

    def debug_valid_targets_for_action(action, target)
        valid_targets = []
        target.each do |item|
          puts "  #{item} can be #{action} ?"
          item =~ /^([a-zA-Z][a-zA-Z]?)\d+$/ and pfx = $1
          puts "pfx for #{item} is #{pfx}"
          art_sym    = @prefix.invert[pfx.upcase]
          puts "artifact_sym for #{pfx} is :#{art_sym}"
          art_states = @states[art_sym]
          puts "valid art_states for #{pfx} is #{art_states.inspect}"  
          valid_targets << item if art_states.include?(action)
        end
        return valid_targets
    end


end

