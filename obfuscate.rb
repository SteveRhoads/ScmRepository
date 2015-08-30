# Copyright 2002-2012 Rally Software Development Corp. All Rights Reserved.

require "base64"

# This really basic algorithm obfuscates but does not encrypt strings
# I want to use the same XML field for both regular and @encoded passwords

#Thanks to Erika for the idea about adding some text at the beginning of the @encoded password
# This clues people in that the password is @encoded and also makes sure that the encoding decoding will never fail.
# Without the extra text, "It will fail if a password has the same number of separators as characters"



#TODO - The first time we read the config file, just encode the passwords...

class Obfuscate
  SEPARATOR = "-"
  ENCODED = "encoded" + SEPARATOR

  def self.encode(string)
    encoded = ""
    Base64.encode64(string).each_byte { |b|
      if ( b != 10 ) # \n
        encoded = encoded + b.chr + SEPARATOR
      end
    }
    return ENCODED + encoded
  end

  def self.decode(string)
    if ( self.encoded?(string))
      decoded = self.remove_every_second_char(string.slice(ENCODED.length,string.length))
      return Base64.decode64(decoded)
    else
      return string
    end
  end


  #Does it start with "encoded-" and are there an equal number of separator strings and regular characters?
  def self.encoded?(string)
    sliced = string.slice(ENCODED.length,string.length)
    return string.slice(0,ENCODED.length) == ENCODED && sliced.length == sliced.count(SEPARATOR)*2
  end

  private
  def self.remove_every_second_char(string)
    no_separators = ""
    for i in 0..string.length-1
      if i%2 == 0
        no_separators = no_separators + string.slice(i, 1)
      end
    end
    return no_separators
  end

end

