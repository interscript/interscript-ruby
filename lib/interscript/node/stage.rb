class Interscript::Node::Stage < Interscript::Node::Group::Sequential
  attr_accessor :name, :doc_name, :dont_reverse

  def initialize(name = :main, reverse_run: nil, doc_name: nil, dont_reverse: false)
    @name = name
    @doc_name = doc_name
    @dont_reverse = dont_reverse
    super(reverse_run: reverse_run)
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :children => @children.map{|x| x.to_hash} }
  end

  def reverse
    return self if dont_reverse

    @reverse ||= begin
      self.class.new(name,
        doc_name: Interscript::Node::Document.reverse_name(doc_name),
        reverse_run: reverse_run.nil? ? nil : !reverse_run
      ).tap do |r|
        r.children = self.children.reverse.map(&:reverse)
      end
    end
  end

  def ==(other)
    super &&
    self.name == other.name &&
    self.reverse_run == other.reverse_run &&
    self.dont_reverse == other.dont_reverse
  end

  def inspect
    args = []
    args << "#{@name}" if @name != :main
    args << "dont_reverse: true" if dont_reverse
    name = ""
    name = "(#{args.join(", ")})" unless args.empty?
    "stage#{name} {\n#{super}\n}"
  end
end
