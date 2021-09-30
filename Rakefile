require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :compile, [:compiler, :target] do |t, args|
  require "interscript"

  compiler, ext = case args[:compiler]
  when "ruby"
    require "interscript/compiler/ruby"
    [Interscript::Compiler::Ruby, "rb"]
  when "javascript"
    require "interscript/compiler/javascript"
    [Interscript::Compiler::Javascript, "js"]
  end

  FileUtils.mkdir_p(args[:target])

  maplist = {}

  maps = Interscript.maps
  maps = Interscript.exclude_maps(maps, compiler: compiler, platform: false)
  
  maps.each do |map|
    code = compiler.(map).code
    File.write(args[:target] + "/" + map + "." + ext, code)
    maplist[map] = nil
  end

  Interscript.maps(libraries: true).each do |map|
    code = compiler.(map).code
    File.write(args[:target] + "/" + map + "." + ext, code)
  end

  File.write(args[:target] + "/index.json", maplist.to_json)
end

task :version, [:ver, :part] do |t, args|
  ver = args[:ver]
  part = args[:part]

  rubyver = File.read(rubyfile = __dir__+"/lib/interscript/version.rb")
  jsver   = File.read(jsfile   = __dir__+"/../js/package.json")
  mapsver = File.read(mapsfile = __dir__+"/../maps/interscript-maps.gemspec")

  rubyver = rubyver.gsub(/(VERSION = ")([0-9a-z.-]*)(")/,                "\\1#{ver}\\3")
  jsver   = jsver.gsub(/("version": ")([0-9a-z.-]*)(")/,                 "\\1#{ver}\\3")
  mapsver = mapsver.gsub(/(INTERSCRIPT_MAPS_VERSION=")([0-9a-z.-]*)(")/, "\\1#{ver}\\3")

  File.write(rubyfile, rubyver) if %w[all ruby].include? part
  File.write(jsfile,   jsver) if %w[all js].include? part
  File.write(mapsfile, mapsver) if %w[all maps].include? part
end

task :generate_visualization_html do
  require "fileutils"
  require "interscript"
  require "interscript/visualize"

  FileUtils.rm_rf(dir = __dir__+"/visualizations/")
  FileUtils.mkdir_p(dir)

  Interscript.maps.each do |map|
    html = Interscript::Visualize.(map)
    File.write(dir+map+".html", html)
  end
end

task :generate_metadata_json do
  require "fileutils"
  require "json"
  require "interscript"
  require "interscript/compiler/javascript"

  FileUtils.rm_rf(file = __dir__+"/metadata.json")

  hash = Interscript.maps.map do |map|
    parsed_map = Interscript.parse(map)
    md = parsed_map.metadata.to_hash
    md["test"] = parsed_map.tests&.data&.first
    md["skip_js"] = Interscript.exclude_maps([map],
                      compiler: Interscript::Compiler::Javascript,
                      platform: false,
                    ).empty?
    [map, md]
  end.to_h

  File.write(file, JSON.pretty_generate(hash))
end

task :generate_json do
  require "fileutils"
  require "json"
  require "interscript"

  FileUtils.rm_rf(dir = __dir__+"/json/")
  FileUtils.mkdir_p(dir)

  (Interscript.maps + Interscript.maps(libraries: true)).each do |map|
    json = JSON.pretty_generate(Interscript.parse(map).to_hash)
    File.write(dir+map+".json", json)
  end
end

task :generate_visualization_json do
  require "fileutils"
  require "interscript"
  require "json"
  require "interscript/visualize"

  FileUtils.rm_rf(dir = __dir__+"/vis_json/")
  FileUtils.mkdir_p(dir)

  (Interscript.maps + Interscript.maps(libraries: true)).each do |map_name|
    map = Interscript.parse(map_name)
    map.stages.each do |stage_name, stage|
      json = JSON.pretty_generate(stage.to_visualization_array(map))
      File.write(dir+map_name+"_#{stage_name}.json", json)
    end
  end
end

task :generate_authority_json do
  require "interscript"
  require "json"
  require "iso-639-data"

  FileUtils.rm_rf(dir = __dir__+"/auth_json/")
  FileUtils.mkdir_p(dir)

  %w[iso icao din].each do |auth|
    out = Interscript.maps.select do |map_name|
      map_name.start_with? "#{auth}-"
    end.sort.map do |map_name|
      map = Interscript.parse(map_name)
      tests = map.tests&.data&.first(2)&.transpose || []
      std, lang = map.metadata.data[:language].split(':')

      {
        lang: std.end_with?("-3") ? Iso639Data.iso_639_3[lang]['Ref_Name'] : Iso639Data.iso_639_2[lang]['eng'],
        isoName: map.metadata.data[:name],
        systemName: map_name,
        samples: tests[0] || [],
        english: [],
        result: []
      }
    end

    json = JSON.pretty_generate(out)
    File.write(dir+auth+".json", json)
  end
end

task :default => :spec
