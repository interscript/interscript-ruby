# frozen_string_literal: true

# Differential gate: parse .isc sources under the Ruby-DSL parser and the
# compiled .parg artifact; the capture trees must agree modulo slice
# stringification.
module PargDiff
  module_function

  def normalize(node)
    case node
    when Hash
      node.to_h { |k, v| [k, normalize(v)] }
    when Array
      node.map { |v| normalize(v) }
    when String
      node
    else
      node.respond_to?(:to_s) ? node.to_s : node
    end
  end

  def diff(a, b, path = "")
    return [] if a == b

    if a.is_a?(Hash) && b.is_a?(Hash)
      (a.keys | b.keys).flat_map do |k|
        if !a.key?(k)
          ["#{path}.#{k}: missing in ruby"]
        elsif !b.key?(k)
          ["#{path}.#{k}: missing in parg"]
        else
          diff(a[k], b[k], "#{path}.#{k}")
        end
      end
    elsif a.is_a?(Array) && b.is_a?(Array)
      return ["#{path}: len #{a.size} != #{b.size}"] if a.size != b.size

      a.each_with_index.flat_map { |v, i| diff(v, b[i], "#{path}[#{i}]") }
    else
      ["#{path}: #{a.inspect[0, 60]} != #{b.inspect[0, 60]}"]
    end
  end
end
