require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

desc "Remove javascript files"
task :clean do
  Dir.glob('vendor/assets/javascripts/*').each { |f| File.delete(f) }
  File.delete('aliases.json') if File.exist?('aliases.json')
end

desc "Build Interscript JavaScript"
task :js => ["aliases.json"] do
  puts "creating javascript version..."
  require "opal/builder"
  require "opal/builder_processors"
  require "opal/onigmo"
  require "erb"
  require "json"

  builder = Opal::Builder.new

  # builder.preload << "lib"
  builder.append_paths "lib"

  %w(rambling-trie-opal).each do |gem|
    builder.use_gem gem
  end

  builder.build('interscript/opal/entrypoint.rb')

  File.open("vendor/assets/javascripts/interscript.js", "w+") do |out|
    out << builder.to_s
  end
end

desc "Build Interscript maps for use with Opal"
task :js_maps do
  require "yaml"
  require "fileutils"
  require "json"

  FileUtils.mkdir_p "vendor/assets/maps"

  Dir['maps/*.yaml'].each do |yaml_file|
    stack = [File.basename(yaml_file, ".yaml")]
    loaded = []
    contents = {}

    while cur = stack.pop
      loaded << cur
      file = File.read("maps/#{cur}.yaml")
      yaml = YAML.load(file)
      # Don't bundle inherited maps
      # if yaml["map"]["inherit"]
      #   inh = Array(yaml["map"]["inherit"])
      #   stack += (inh - loaded)
      # end
      contents[cur] = yaml
    end
    f = JSON.dump(contents)
    File.write("vendor/assets/maps/#{File.basename yaml_file, ".yaml"}.json", f)
  end
end

desc "Optimize the resulting Javascript"
task :js_optimize => [:js] do
  require "opal/optimizer"

  js = File.read("vendor/assets/javascripts/interscript.js")
  exports = File.read("lib/interscript/opal/exports.rb")

  opt = Opal::Optimizer.new(js, exports: exports).optimize
  File.write("vendor/assets/javascripts/interscript.opt.js", opt)
end

desc "Correct file names in 'maps' directory to ensure to be uppercase for 3rd and 4rd"
task :rename do
  require "yaml"

  root_path = File.expand_path File.dirname(__FILE__)
  changed = []
  edited = []
  Dir['maps/*.yaml'].each do |yaml_file|
    org_name = File.basename(yaml_file, ".yaml")

    # capitalize file name
    capitalize_filename = proc do |org_name|
      terms = org_name.split("-")
      terms[2].capitalize!
      terms[3].capitalize!
      terms.join("-")
    end

    new_name = capitalize_filename.(org_name)
    new_name_full = root_path + '/maps/' + new_name + ".yaml"

    if org_name != new_name
      File.rename(yaml_file, new_name_full)
      changed << new_name
    end

    # capitalize inherit
    org_file = File.read(new_name_full)
    new_file = org_file
    yaml = YAML.load(org_file)
    dump = Proc.new { |h| YAML.dump(h)[4..-2] }   # [4..-2] removes the initial magic signature from YAML and a new line from the end
    if org_inherit = yaml.dig("map", "inherit")
      new_inherit = case org_inherit
      when Array
        org_inherit.map(&capitalize_filename)
      when String
        capitalize_filename.(org_inherit)
      else
        raise "#{org_inherit} has a type different from String/Array"
      end

      new_file = org_file.gsub(dump.(org_inherit), dump.(org_inherit)) if new_inherit != org_inherit
    end

    # capitalize source_script, destination_script
    h = Proc.new { |x| {x => yaml[x]} }
    ["source_script", "destination_script"].each do |pp|
      new_file = new_file.gsub(dump.(h.(pp)), dump.(h.(pp).tap{|a| a[pp] = yaml[pp].capitalize})) unless yaml[pp] == yaml[pp].capitalize
    end

    if new_file != org_file
      File.write(new_name_full, new_file)
      edited << new_name
    end
  end

  puts "Total Scanned: #{Dir['maps/*.yaml'].size} files"
  puts "Renamed Count: #{changed.size} "
  puts "Fixed Count: #{edited.size} "
  changed.each { |new_name| puts new_name }
end

file "aliases.json" => Dir["maps/*.yaml"] + ["Rakefile"] do
  require "interscript"

  Interscript.aliases(refresh: true)
end

desc "All in one"
task all: [:clean] do
  Rake::Task["js_optimize"].invoke
  Rake::Task["js_maps"].invoke
end

task default: [:spec]
