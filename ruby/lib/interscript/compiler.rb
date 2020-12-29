# An Interscript compiler interface
class Interscript::Compiler
  attr_accessor :code

  def self.call(map)
    if String === map
      map = Interscript::DSL.parse(map)
    end

    new.compile(map)
  end

  def compile(map)
    raise NotImplementedError, "Compile method on #{self.class} is not implemented"
  end

  # Execute a map
  def call
    raise NotImplementedError, "Call class on #{self.class} is not implemented"
  end
end
