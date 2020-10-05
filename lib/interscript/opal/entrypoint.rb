require "opal"
require "onigmo/onigmo-wasm"

module Interscript
  def self.on_load(&block)
    WebAssembly.wait_for("onigmo/onigmo-wasm", &block)
  end
end

Interscript.on_load do
  require "interscript"
end
