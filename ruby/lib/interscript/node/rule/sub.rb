class Interscript::Node::Rule::Sub < Interscript::Node::Rule
  attr_accessor :from, :to, :params


  def initialize from, to,**kargs
    puts "Interscript::Node::Rule::Sub.new (args = #{
      args.inspect
    }, kargs = #{
      kargs.inspect
    })" if $DEBUG

    if from.class == String
      self.from = Interscript::Node::Item::Character.new from
    else
      self.from = from
    end
    if to.class == String
      self.to = Interscript::Node::Item::Character.new to
    else
      self.to = to
    end
    self.params = kargs if kargs
  end




  def to_hash
    puts self.from.inspect if $DEBUG
    puts params.inspect if $DEBUG
    {:class => self.class.to_s,
      :from => self.from.to_hash,
      :to => self.to.to_hash,
      :params => self.params.each_with_object({}){ |pair,hash|
        hash[pair[0]] = pair[1].to_hash
      }
    }
  end



end
