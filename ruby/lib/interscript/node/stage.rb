class Interscript::Node::Stage < Interscript::Node::Group::Sequential
  attr_accessor :name, :doc_name

  def initialize(name = :main, reverse_run: nil, doc_name: nil)
    @name = name
    @doc_name = doc_name
    super(reverse_run: reverse_run)
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :children => @children.map{|x| x.to_hash} }
  end

  def reverse
    @reverse ||= begin
      self.class.new(name,
        doc_name: Interscript::Node::Document.reverse_name(doc_name),
        reverse_run: reverse_run.nil? ? nil : !reverse_run
      ).tap do |r|
        r.children = self.children.reverse.map(&:reverse)
      end
    end
  end

  def inspect
    name = "(#{@name})" if @name != :main
    "stage#{name} {\n#{super}\n}"
  end
end
