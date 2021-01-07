class Interscript::DSL::Metadata
  attr_accessor :node

  def initialize(yaml: false, &block)
    raise ArgumentError, "Can't evaluate metadata from Ruby context" unless yaml
    @node = Interscript::Node::MetaData.new
    self.instance_exec(&block)
  end

  %i{authority_id id language source_script
    destination_script name url creation_date
    adoption_date description character notes
    source confirmation_date}.each do |sym|
    define_method sym do |stuff|
      @node[sym] = stuff
    end
  end
end
