require "opal"
require "interscript/opal/maps"
require "onigmo/onigmo-wasm"

module Interscript
  def self.on_load(&block)
    WebAssembly.wait_for("onigmo/onigmo-wasm", &block)
  end

  # on_load + load_maps
  def self.on_load_maps(arg, &block)
    self.on_load.JS.then do
      self.load_maps(arg, &block)
    end
  end
end

Interscript.on_load do
  require "interscript"
end
