require 'bigdecimal'
require 'date'
require 'ipaddr'
require 'time'

# Checks that the values the generated code returns are instances of the types the generated .rbs declares
# for them (dependency free: reads `attr_reader name: Type` lines instead of loading the signatures).
module RbsTypes
  module_function

  SOURCES = {} # rubocop:disable Style/MutableConstant

  # Read once, before any query runs: File.read inside a fiber scheduler raises EBADF on Windows (Ruby 3.1 + async)
  def source(path) = SOURCES[path] ||= File.read(path)

  # { 'c_date' => 'Date?', ... } for `class <class_name>` in an .rbs file
  def attributes(rbs_path, class_name)
    body = source(rbs_path)[/^( *)class #{Regexp.escape(class_name)}(?: < [^\n]+)?\n(.*?)^\1end$/m, 2] or
      raise "#{class_name} not in #{rbs_path}"
    body.scan(/attr_(?:reader|accessor) (\w+): (.+)$/).to_h { |name, type| [name, top_level(type)] }
  end

  # `::Array[::String]` -> `Array[String]`: the generated RBS roots core types so models cannot shadow them.
  def top_level(type)
    type.gsub(/(?<![\w:])::(?=[A-Z])/, '')
  end

  # Returns the list of mismatches (empty when every attribute value has its declared type).
  def mismatches(row, rbs_path, class_name)
    attributes(rbs_path, class_name).filter_map do |name, type|
      value = row.public_send(name)
      next if matches?(value, type)

      "#{class_name}##{name}: declared #{type}, got #{value.class} (#{value.inspect[0, 40]})"
    end
  end

  def install(query_class, rbs_path)
    return unless File.file?(rbs_path)

    module_name = query_class.name.sub(/::QuerySql\z/, '')
    models_path = File.join(File.dirname(rbs_path), 'models.rbs')
    source(models_path) if File.file?(models_path)
    signatures = source(rbs_path).scan(/^\s+def ([\w!?]+):.*?-> (.+)$/).to_h { |name, type| [name, top_level(type)] }
    methods = query_class.public_instance_methods(false).filter_map do |name|
      type = signatures[name.to_s]
      [name, type] if type && type != 'T' && name != :transaction
    end
    checker = Module.new do
      methods.each do |name, type|
        define_method(name) do |*args, **kwargs, &block|
          value = super(*args, **kwargs, &block)
          errors = RbsTypes.return_mismatches(value, type, rbs_path, module_name)
          raise TypeError, "#{self.class}##{name}: #{errors.join('; ')}" unless errors.empty?

          value
        end
      end
    end
    query_class.prepend(checker)
  end

  def return_mismatches(value, type, rbs_path, module_name)
    return [] if %w[untyped untyped?].include?(type)
    return ['expected nil'] if type == 'void' && !value.nil?
    return [] if type == 'void'

    optional = type.end_with?('?')
    type = type.delete_suffix('?')
    return optional ? [] : ["expected #{type}, got nil"] if value.nil?

    if (element_type = type[/\AArray\[(.*)\]\z/, 1])
      return ["expected Array, got #{value.class}"] unless value.is_a?(Array)
      element_type += '?' unless element_type.end_with?('?')

      return value.each_with_index.flat_map do |element, index|
        return_mismatches(element, element_type, rbs_path, module_name).map { |error| "[#{index}] #{error}" }
      end
    end

    if type == 'bool'
      return [true, false].include?(value) ? [] : ["expected bool, got #{value.class}"]
    end
    klass = resolve_type(type, module_name)
    return ["expected #{type}, got #{value.class}"] unless klass && value.is_a?(klass)
    return [] unless klass.is_a?(Module) && klass.name.to_s.start_with?("#{module_name}::")

    class_name = type.split('::').last
    class_rbs_path = [rbs_path, File.join(File.dirname(rbs_path), 'models.rbs')].find do |path|
      File.file?(path) && rbs_has_class?(path, class_name)
    end
    return [] unless class_rbs_path

    attributes(class_rbs_path, class_name).flat_map do |name, attribute_type|
      nested = return_mismatches(value.public_send(name), attribute_type, rbs_path, module_name)
      nested.map { |error| "#{class_name}##{name} #{error}" }
    end
  end

  def resolve_type(type, module_name)
    return { 'String' => String, 'Integer' => Integer, 'Float' => Float, 'BigDecimal' => BigDecimal,
             'Date' => Date, 'Time' => Time, 'IPAddr' => IPAddr, 'bool' => [TrueClass, FalseClass],
             'nil' => NilClass }[type] if
      %w[String Integer Float BigDecimal Date Time IPAddr bool nil].include?(type)

    ["#{module_name}::#{type}", "#{module_name}::QuerySql::#{type}"].each do |name|
      return Object.const_get(name)
    rescue NameError
      next
    end
    nil
  end

  def rbs_has_class?(rbs_path, class_name)
    source(rbs_path).match?(/^\s*class #{Regexp.escape(class_name)}(?: < [^\n]+)?$/)
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
