require 'date'

class Interscript::DSL::Metadata
  attr_accessor :node

  def initialize(yaml: false, map_name: "", library: true, &block)
    raise ArgumentError, "Can't evaluate metadata from Ruby context" unless yaml
    @map_name = map_name
    @node = Interscript::Node::MetaData.new
    self.instance_exec(&block)
    @node[:nonstandard] = {}

    NECESSARY_KEYS.each do |i|
      unless @node.data.key? i
        warn "[#{@map_name}] Necessary key #{i} wasn't defined. Defaulting to an empty string"
        @node[i] = ""
      end
    end unless library
  end

  STANDARD_STRING_KEYS = %i{authority_id id
  language source_script destination_script
  name url creation_date adoption_date description
  character source confirmation_date}

  STANDARD_ARRAY_KEYS = %i{notes}

  NONSTANDARD_KEYS = %i{special_rules original_description original_notes
    implementation_notes}
  
  NECESSARY_KEYS = %i{name language source_script destination_script}

  STANDARD_STRING_KEYS.each do |sym|
    define_method sym do |stuff|
      case stuff
      when String, Integer, Date
        @node[sym] = stuff.to_s
      when NilClass
      else
        warn "[#{@map_name}] Metadata key #{sym} expects a String, but #{stuff.class} was given"
        @node[sym] = stuff.inspect
      end
    end
  end

  STANDARD_ARRAY_KEYS.each do |sym|
    define_method sym do |stuff|
      stuff = Array(stuff)

      stuff.map do |i|
        case i
        when String
          i
        else
          warn "[#{@map_name}] Metadata key #{sym} expects all Array elements to be String"
          i.inspect
        end
      end
    end
  end

  NONSTANDARD_KEYS.each do |sym|
    define_method sym do |stuff|
      warn "[#{@map_name}] Metadata key #{sym} is non-standard"
      (@node[:nonstandard] ||= {})[sym] = stuff
    end
  end
end
