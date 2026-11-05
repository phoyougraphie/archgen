# frozen_string_literal: true

module Archgen
  module Core
    # Parseur JSON borné. Le parseur standard accepte les clés dupliquées et ne
    # borne ni la profondeur à la demande ni la taille : on en écrit un dédié.
    class StrictJson
      Error = Class.new(StandardError) do
        attr_reader :path

        def initialize(message, path = '')
          super(message)
          @path = path
        end
      end

      ESCAPES = { '"' => '"', '\\' => '\\', '/' => '/', 'b' => "\b", 'f' => "\f",
                  'n' => "\n", 'r' => "\r", 't' => "\t" }.freeze
      NUMBER = /-?(?:0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/
      MAX_NUMBER_CHARS = 64

      # Retourne un Result dont la valeur est l'arbre JSON (clés chaînes).
      def self.parse(text, max_bytes: Limits::JSON_BYTES, max_depth: Limits::JSON_DEPTH)
        return failure('not_a_string') unless text.is_a?(String)
        return failure('too_large', limit: max_bytes) if text.bytesize > max_bytes

        utf8 = text.dup.force_encoding('UTF-8')
        return failure('invalid_utf8') unless utf8.valid_encoding?

        Result.ok(new(utf8, max_depth).document)
      rescue Error => e
        failure(e.message, path: e.path)
      end

      def self.failure(reason, path: '', **params)
        Result.fail([Diagnostic.error('E_SCHEMA', path, reason: reason, **params)])
      end
      private_class_method :failure

      def initialize(text, max_depth)
        @text = text
        @pos = 0
        @max_depth = max_depth
      end

      def document
        value = parse_value('', 1)
        skip_ws
        raise Error, 'trailing_data' unless @pos == @text.length

        value
      end

      private

      def skip_ws
        @pos += 1 while @pos < @text.length && " \t\n\r".include?(@text[@pos])
      end

      def parse_value(path, depth)
        skip_ws
        case @text[@pos]
        when '{' then parse_object(path, depth)
        when '[' then parse_array(path, depth)
        when '"' then parse_string(path)
        when 't' then literal('true', true, path)
        when 'f' then literal('false', false, path)
        when 'n' then literal('null', nil, path)
        else parse_number(path)
        end
      end

      def literal(word, value, path)
        raise Error.new('invalid_json', path) unless @text[@pos, word.length] == word

        @pos += word.length
        value
      end

      def check_depth(path, depth)
        raise Error.new('too_deep', path) if depth > @max_depth
      end

      def parse_object(path, depth)
        check_depth(path, depth)
        @pos += 1
        result = {}
        skip_ws
        if @text[@pos] == '}'
          @pos += 1
          return result
        end
        loop do
          skip_ws
          raise Error.new('invalid_json', path) unless @text[@pos] == '"'

          key = parse_string(path)
          child = "#{path}/#{pointer_escape(key)}"
          raise Error.new('duplicate_key', child) if result.key?(key)

          skip_ws
          raise Error.new('invalid_json', child) unless @text[@pos] == ':'

          @pos += 1
          result[key] = parse_value(child, depth + 1)
          break if separator?('}', path)
        end
        result
      end

      def parse_array(path, depth)
        check_depth(path, depth)
        @pos += 1
        result = []
        skip_ws
        if @text[@pos] == ']'
          @pos += 1
          return result
        end
        loop do
          result << parse_value("#{path}/#{result.size}", depth + 1)
          break if separator?(']', path)
        end
        result
      end

      # Consomme `,` (retourne false) ou le fermant (retourne true).
      def separator?(closer, path)
        skip_ws
        case @text[@pos]
        when ',' then @pos += 1
                      false
        when closer then @pos += 1
                         true
        else raise Error.new('invalid_json', path)
        end
      end

      def parse_number(path)
        match = NUMBER.match(@text, @pos)
        raise Error.new('invalid_json', path) unless match && match.begin(0) == @pos

        token = match[0]
        raise Error.new('number_too_long', path) if token.length > MAX_NUMBER_CHARS

        @pos += token.length
        return Integer(token, 10) unless match[1] || match[2]

        value = Float(token)
        raise Error.new('non_finite_number', path) unless value.finite?

        value
      end

      def parse_string(path)
        @pos += 1
        out = +''
        loop do
          char = @text[@pos]
          raise Error.new('invalid_json', path) if char.nil?

          @pos += 1
          case char
          when '"' then return out
          when '\\' then out << parse_escape(path)
          else
            raise Error.new('control_character', path) if char.ord < 0x20

            out << char
          end
        end
      end

      def parse_escape(path)
        char = @text[@pos]
        @pos += 1
        return ESCAPES[char] if ESCAPES.key?(char)
        raise Error.new('invalid_escape', path) unless char == 'u'

        code = hex4(path)
        return [code].pack('U') unless (0xD800..0xDFFF).cover?(code)
        raise Error.new('lone_surrogate', path) if code >= 0xDC00 || @text[@pos, 2] != '\\u'

        @pos += 2
        low = hex4(path)
        raise Error.new('lone_surrogate', path) unless (0xDC00..0xDFFF).cover?(low)

        [0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)].pack('U')
      end

      def hex4(path)
        token = @text[@pos, 4]
        raise Error.new('invalid_escape', path) unless token&.match?(/\A\h{4}\z/)

        @pos += 4
        token.to_i(16)
      end

      def pointer_escape(key)
        key.gsub('~', '~0').gsub('/', '~1')
      end
    end
  end
end
