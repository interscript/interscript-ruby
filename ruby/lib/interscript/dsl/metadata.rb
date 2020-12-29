class Interscript::DSL::Metadata
  attr_accessor :node

  def initialize(&block)
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
