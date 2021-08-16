require "text"

class Interscript::Detector
  attr_accessor :compiler
  attr_accessor :distance_computer
  attr_accessor :map_pattern

  # TODO: use transliterate_each
  attr_accessor :each

  attr_accessor :load_path
  attr_accessor :cache

  # Returns a summary of all detected transliterations
  attr_accessor :multiple

  def initialize
    @compiler = Interscript::Interpreter
    @distance_computer = DistanceComputer::Levenshtein
    @map_pattern = "*"

    @each = false

    @load_path = false
    @cache = CACHE
  end

  def set_from_kwargs(**kwargs)
    kwargs.each do |k,v|
      self.public_send(:"#{k}=", v)
    end
  end

  def call(source, destination)
    maps = Interscript.maps(select: @map_pattern, load_path: @load_path)
    maps = Interscript.exclude_maps(maps, compiler: self.class)
    maps = Interscript.exclude_maps(maps, compiler: @compiler)

    summary = maps.map do |map|
      try_dest = Interscript.transliterate(map, source, compiler: @compiler)

      [map, try_dest]
    end.map do |map, try_dest|
      dist = @distance_computer.(try_dest, destination)
      
      [map, dist]
    end.sort_by(&:last).to_h

    if @multiple
      summary.to_h
    else
      summary.first.first
    end
  end

  CACHE = {}

  # A DistanceComputer needs to respond to #call(source, destination)
  module DistanceComputer
    Levenshtein = Text::Levenshtein.method(:distance)
  end
end