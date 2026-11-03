require 'bigdecimal'
require 'date'
require 'ipaddr'
require 'time'

# Checks that the values the generated code returns are instances of the types the generated .rbs declares
# for them (dependency free: reads `attr_reader name: Type` lines instead of loading the signatures).
module RbsTypes
  module_function

  # { 'c_date' => 'Date?', ... } for `class <class_name>` in an .rbs file
  def attributes(rbs_path, class_name)
    body = File.read(rbs_path)[/^( *)class #{Regexp.escape(class_name)}(?: < [^\n]+)?\n(.*?)^\1end$/m, 2] or
      raise "#{class_name} not in #{rbs_path}"
    body.scan(/attr_(?:reader|accessor) (\w+): (.+)$/).to_h
  end

  # Returns the list of mismatches (empty when every attribute value has its declared type).
  def mismatches(row, rbs_path, class_name)
    attributes(rbs_path, class_name).filter_map do |name, type|
      value = row.public_send(name)
      next if matches?(value, type)

      "#{class_name}##{name}: declared #{type}, got #{value.class} (#{value.inspect[0, 40]})"
    end
  end

  def matches?(value, type)
    optional = type.end_with?('?')
    type = type.chomp('?')
    return true if type == 'untyped'
    return optional if value.nil?

    case type
    when 'bool' then [true, false].include?(value)
    when /\AArray\[(.+)\]\z/ then value.is_a?(Array) && value.all? { |v| matches?(v, "#{Regexp.last_match(1)}?") }
    else value.is_a?(Object.const_get(type))
    end
  end
end
