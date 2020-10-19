require "onigmo"
require "onigmo/core_ext"

# Increase this if there are out-of-memory errors. This setting is
# tested to be big enough to handle all the maps provided.
Onigmo::FFI.library.memory.grow(128)

module Interscript
  module Opal
    def mkregexp(regexpstring)
      @cache ||= {}
      if s = @cache[regexpstring]
        s
      else
        # JS regexp is more performant than Onigmo. Let's use the JS
        # regexp wherever possible, but use Onigmo where we must.
        # Let's allow those characters to happen for the regexp to be
        # considered compatible: ()|.*+?{} ** BUT NOT (? **.
        if /[\\$^\[\]]|\(\?/.match?(regexpstring)
          # Ruby caches its regexps internally. We can't GC. We could
          # think about freeing them, but we really can't, because they
          # may be in use.

          # Uncomment those to keep track of Onigmo/JS regexp compilation.
          # print '#'
          @cache[regexpstring] = Onigmo::Regexp.new(regexpstring)
        else
          # print '.'
          @cache[regexpstring] = Regexp.new(regexpstring)
        end
      end
    end

    def sub_replace(string, pos, size, repl)
      string[0, pos] + repl + string[pos + size..-1]
    end

    def external_processing(mapping, string)
      string
    end

    def load_map_json(_, json)
      json = Hash.new(json) if native? json
      json = JSON.load(json) if String === json
      json.each do |k,v|
        `Opal.global.InterscriptMaps[#{k}] = #{JSON.dump(v)}`
      end
    end

    # Use #on_load_maps if possible. It will be available earlier.
    # See lib/interscript/opal/entrypoint.rb
    def load_maps(opts, &block)
      # Convert arg
      opts = Hash.new(opts) if native? opts

      defaults = {
        maps: [],
        path: nil,
        node_path: "./maps/",
        ajax_path: "maps/",
        loader: nil,
        processor: proc { |i| i },
      }

      opts = defaults.merge opts
      opts[:maps] = Array(opts[:maps])

      %x{
        var ajax_loader = function(map) {
          return new Promise(function(ok, fail) {
            var httpRequest = new XMLHttpRequest();
            httpRequest.onreadystatechange = function() {
              if (httpRequest.readyState === XMLHttpRequest.DONE) {
                if (httpRequest.responseText) {
                  ok(JSON.parse(httpRequest.responseText));
                }
                else {
                  if (is_local) {
                    console.log(httpRequest.responseText);
                    fail("Ajax failed load: "+map+". Status: "+httpRequest.statusText+". "+
                      "Are you running this locally? Try adding: "+
                      "--allow-file-access-from-files to your Chromium command line.")
                  }
                  else fail("Ajax failed load: "+map+". Status: "+httpRequest.statusText);
                }
              }
            };
            httpRequest.open('GET', #{opts[:path] || opts[:ajax_path]}+map+".json", true);
            httpRequest.send();
          });
        };

        var fetch_loader = function(map) {
          return fetch(#{opts[:path] || opts[:ajax_path]}+map+".json").then(function(response) {
            return response.json();
          });
        };

        var node_loader = function(map) {
          var resolve = null, error = null;
          var prom = new Promise(function(ok, fail) {
            resolve = ok;
            error = fail;
          });
          try {
            resolve(require(#{opts[:path] || opts[:node_path]}+map+'.json'));
          }
          catch(e) {
            error("Node failed load: "+map+". Error: "+e);
          }
          return prom;
        };

        var is_local = false;
        if (typeof document !== "undefined" &&
            typeof document.location !== "undefined" &&
            typeof document.location.protocol !== "undefined") {
              is_local = document.location.protocol == "file:";
            }

        var loader = function(map) {
          if (#{opts[:loader] != nil}) {
            return #{opts[:loader]}(#{opts[:path]}+map+'.json').then(#{opts[:processor]});
          }
          else if (typeof global !== "undefined") {
            return node_loader(map);
          }
          else if (!is_local && typeof fetch === "function") {
            return fetch_loader(map);
          }
          else if (typeof window !== "undefined") {
            return ajax_loader(map);
          }
          else {
            #{raise StandardError, "We couldn't find a good way to load a map"}
          }
        };
      }

      prom = `new Promise(function(ok, fail) {
        #{
          maps = opts[:maps]
          maps = maps.map { |i| map_resolve i }
          maps = maps.reject { |i| map_loaded? i }
          #p ["Loading:", maps]
          maps = maps.map do |i|
            `loader(#{i})`.JS.then do |map|
              load_map_json(nil, map)

              m = Native(map)
              inherits = []
              m.each do |mapname, mapvalue|
                inherits += Array(Native(mapvalue)[:map][:inherit])
                inherits += Array(Native(mapvalue)[:chain])
              end
              inherits = inherits.uniq
              inherits = inherits.reject { |i| map_loaded? i }

              load_maps(opts.merge({maps: inherits})) unless inherits.empty?
            end.JS.catch do |response|
              `fail(#{response})`
            end
          end
        }
        Promise.all(#{maps}).then(ok).catch(fail);
      })`

      if block_given?
        prom.JS.then(block)
      else
        prom
      end
    end

    def aliases
      @aliases ||= Hash.new(`Opal.global.InterscriptMapAliases`)
    end

    def map_exist?(map)
      `typeof(Opal.global.InterscriptMaps[#{map}]) !== 'undefined'`
    end

    def map_loaded?(map)
      `!!Opal.global.InterscriptMaps[#{map}]`
    end
  end
end

class String
  # Opal has a wrong implementation of String#unicode_normalize
  def unicode_normalize
    self.JS.normalize
  end
end
