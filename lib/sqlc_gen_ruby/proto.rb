# frozen_string_literal: true

# A tiny, dependency-free protobuf (proto3) wire-format codec.
#
# The official `google-protobuf` gem is a C extension and cannot be loaded by a
# ruby.wasm interpreter, so the plugin carries its own minimal implementation.
# Only the features sqlc's plugin protocol needs are supported: varints, length
# delimited fields (string/bytes/messages), repeated fields. Unknown fields are
# skipped on decode.
module SqlcGenRuby
  module Proto
    VARINT = 0
    FIXED64 = 1
    LEN = 2
    FIXED32 = 5

    Field = Struct.new(:name, :number, :type, :repeated, :klass)

    class Message
      class << self
        def fields
          @fields ||= []
        end

        # scalar types: :string, :bytes, :bool, :int32, :int64, :uint32, :uint64
        # message types: :message with `klass:`
        def field(name, number, type, repeated: false, klass: nil)
          fields << Field.new(name, number, type, repeated, klass)
          attr_writer name
          if repeated
            define_method(name) { instance_variable_get("@#{name}") || instance_variable_set("@#{name}", []) }
          else
            default = default_for(type)
            define_method(name) do
              v = instance_variable_get("@#{name}")
              v.nil? ? (default.dup rescue default) : v
            end
          end
        end

        def default_for(type)
          case type
          when :string then ''
          when :bytes then ''.b
          when :bool then false
          when :message then nil
          else 0
          end
        end

        def decode(data)
          msg = new
          reader = Reader.new(data)
          until reader.eof?
            number, wire = reader.read_tag
            f = fields.find { |fd| fd.number == number }
            if f.nil?
              reader.skip(wire)
              next
            end
            value = reader.read_value(f, wire)
            if f.repeated
              msg.public_send(f.name) << value
            else
              msg.public_send("#{f.name}=", value)
            end
          end
          msg
        end
      end

      def initialize(**attrs)
        attrs.each { |k, v| public_send("#{k}=", v) }
      end

      def encode
        out = ''.b
        self.class.fields.each do |f|
          values = f.repeated ? public_send(f.name) : [instance_variable_get("@#{f.name}")]
          values.each do |v|
            next if v.nil?
            next if !f.repeated && v == self.class.default_for(f.type)

            Writer.write_field(out, f, v)
          end
        end
        out
      end
    end

    class Reader
      def initialize(data)
        @data = data.b
        @pos = 0
      end

      attr_reader :pos

      def eof?
        @pos >= @data.bytesize
      end

      def read_varint
        result = 0
        shift = 0
        loop do
          raise 'truncated varint' if eof?

          byte = @data.getbyte(@pos)
          @pos += 1
          result |= (byte & 0x7f) << shift
          return result if byte < 0x80

          shift += 7
        end
      end

      def read_tag
        tag = read_varint
        [tag >> 3, tag & 7]
      end

      def read_bytes
        len = read_varint
        raise 'truncated field' if @pos + len > @data.bytesize

        s = @data.byteslice(@pos, len)
        @pos += len
        s
      end

      def skip(wire)
        case wire
        when VARINT then read_varint
        when FIXED64 then @pos += 8
        when LEN then read_bytes
        when FIXED32 then @pos += 4
        else raise "unsupported wire type #{wire}"
        end
      end

      def read_value(field, wire)
        case field.type
        when :string then expect(wire, LEN) { read_bytes.force_encoding(Encoding::UTF_8) }
        when :bytes then expect(wire, LEN) { read_bytes }
        when :message then expect(wire, LEN) { field.klass.decode(read_bytes) }
        when :bool then expect(wire, VARINT) { read_varint != 0 }
        when :int32 then expect(wire, VARINT) { to_signed(read_varint, 32) }
        when :int64 then expect(wire, VARINT) { to_signed(read_varint, 64) }
        when :uint32, :uint64 then expect(wire, VARINT) { read_varint }
        else raise "unsupported type #{field.type}"
        end
      end

      private

      def expect(wire, wanted)
        raise "wire type mismatch: got #{wire}, want #{wanted}" unless wire == wanted

        yield
      end

      # int32 and int64 are both sign-extended to 64 bits on the wire.
      def to_signed(v, _bits)
        v >= (1 << 63) ? v - (1 << 64) : v
      end
    end

    module Writer
      module_function

      def varint(out, n)
        n &= 0xffffffffffffffff if n.negative?
        loop do
          byte = n & 0x7f
          n >>= 7
          if n.zero?
            out << byte.chr
            break
          end
          out << (byte | 0x80).chr
        end
      end

      def write_field(out, f, v)
        case f.type
        when :string, :bytes, :message
          payload = f.type == :message ? v.encode : v.to_s.b
          varint(out, (f.number << 3) | LEN)
          varint(out, payload.bytesize)
          out << payload
        when :bool
          varint(out, (f.number << 3) | VARINT)
          varint(out, v ? 1 : 0)
        else
          varint(out, (f.number << 3) | VARINT)
          varint(out, v)
        end
      end
    end
  end
end
