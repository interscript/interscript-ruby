# frozen_string_literal: true

require "json"

# JSON IR compiler — emits a data-only intermediate representation consumable
# by non-Ruby runtimes (e.g. interscript-ts). Unlike Compiler::Javascript,
# which emits imperative JS that calls into a runtime, this emits a pure-data
# JSON document describing the AST.
#
# The shape is versioned via SCHEMA_VERSION. Runtimes should refuse to load
# IR with an unknown schema.
class Interscript::Compiler::JsonIR < Interscript::Compiler
  SCHEMA_VERSION = 1

  CompiledResult = Struct.new(:code) do
    # JsonIR output is already JSON. The runtime treats .code as opaque
    # text; consumers parse via JSON.parse.
    def to_json(*)
      code
    end
  end

  def compile(map, debug: false)
    @map = map
    @c = JSON.pretty_generate(serialise_document(map))
    self
  end

  def code
    @c
  end

  private

  def serialise_document(doc)
    {
      schemaVersion: SCHEMA_VERSION,
      systemCode: doc.name.to_s,
      dependencies: doc.dependencies.map(&:full_name),
      metadata: serialise_metadata(doc.metadata),
      stages: serialise_stages(doc.stages),
      aliases: serialise_aliases(doc.aliases),
      functions: {}
    }
  end

  def serialise_metadata(metadata)
    return {} unless metadata
    out = {}
    metadata.data.each do |k, v|
      out[k.to_s] = case v
                    when Symbol then v.to_s
                    else v
                    end
    end
    out
  end

  def serialise_stages(stages)
    # Document#stages returns Hash{name => Stage} for the document's own stages,
    # but may also include imported stages. Iterate values and skip anything
    # that isn't an Interscript::Node::Stage (e.g. imported Hash entries).
    stages.values.map { |s| serialise_stage(s) if s.is_a?(Interscript::Node::Stage) }.compact
  end

  def serialise_stage(stage)
    {
      kind: "stage",
      name: stage.name.to_s,
      rules: stage.children.map { |r| serialise_rule(r) }
    }
  end

  def serialise_rule(rule)
    case rule
    when Interscript::Node::Rule::Sub
      serialise_sub_rule(rule)
    when Interscript::Node::Rule::Run
      serialise_run_rule(rule)
    when Interscript::Node::Rule::Funcall
      serialise_funcall_rule(rule)
    when Interscript::Node::Group::Parallel
      # Parallel rule groups contain sub-rules that are applied simultaneously.
      # In IR, we emit them as a marker rule so the runtime can decide.
      {
        kind: "parallel",
        rules: rule.children.map { |r| serialise_rule(r) }
      }
    when Interscript::Node::Group::Sequential
      {
        kind: "sequential",
        rules: rule.children.map { |r| serialise_rule(r) }
      }
    else
      raise Interscript::MapLogicError, "Cannot serialise rule of type #{rule.class}"
    end
  end

  def serialise_sub_rule(rule)
    out = {kind: "sub"}
    out[:from] = serialise_item(rule.from) if rule.from
    out[:to] = serialise_to(rule.to)
    out[:before] = serialise_item(rule.before) if rule.before
    out[:after] = serialise_item(rule.after) if rule.after
    out[:notBefore] = serialise_item(rule.not_before) if rule.not_before
    out[:notAfter] = serialise_item(rule.not_after) if rule.not_after
    out[:priority] = rule.priority if rule.priority
    out
  end

  def serialise_run_rule(rule)
    stage = rule.stage
    doc_name = stage.map
    if doc_name && @map.respond_to?(:dep_aliases) && @map.dep_aliases[doc_name.to_sym]
      resolved = @map.dep_aliases[doc_name.to_sym].document
      doc_name = resolved.name.to_s if resolved && resolved.respond_to?(:name)
    end
    {
      kind: "run",
      stage: stage.name.to_s,
      docName: doc_name&.to_s
    }
  end

  def serialise_funcall_rule(rule)
    {
      kind: "funcall",
      name: rule.name.to_s,
      kwargs: symbolise_keys(rule.kwargs)
    }
  end

  def serialise_to(to)
    case to
    when Symbol
      {kind: "funcall_inline", name: to.to_s}
    else
      serialise_item(to)
    end
  end

  def serialise_item(item)
    case item
    when Interscript::Node::Item::String
      {kind: "string", value: item.data}
    when Interscript::Node::Item::CaptureGroup
      {kind: "capture_group", data: serialise_item(item.data)}
    when Interscript::Node::Item::CaptureRef
      {kind: "capture_ref", id: item.id}
    when Interscript::Node::Item::Alias
      out = {kind: "alias", name: item.name.to_s}
      out[:map] = item.map if item.map
      out
    when Interscript::Node::Item::Any
      data = item.data || []
      {kind: "any", of: data.map { |i| serialise_item(i) }}
    when Interscript::Node::Item::Group
      {kind: "group", items: item.children.map { |i| serialise_item(i) }}
    when Interscript::Node::Item::Repeat
      {kind: "repeat", item: serialise_item(item.data), min: 0, max: Float::INFINITY}
    when Interscript::Node::Item::Stage
      {kind: "stage_ref", name: item.name.to_s}
    when nil
      nil
    else
      raise Interscript::MapLogicError, "Cannot serialise item of type #{item.class}"
    end
  end

  def capture_index(_item)
    # CaptureGroup index is determined by position in pattern compilation.
    # Runtimes should treat as a placeholder; the actual index is computed
    # during pattern compilation based on capture-group ordering.
    0
  end

  def serialise_aliases(aliases)
    out = {}
    aliases.each do |name, defn|
      out[name.to_s] = serialise_item(defn.data)
    end
    out
  end

  def symbolise_keys(hash)
    return {} if hash.nil?
    hash.transform_keys(&:to_s)
  end
end
