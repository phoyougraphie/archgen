# frozen_string_literal: true

require 'digest/sha2'
require 'json'

module Archgen
  module Core
    # JSON canonique : clés triées (octets), UTF-8, tableaux en ordre métier,
    # nombres finis, jamais -0. Base de toutes les empreintes.
    module Canonical
      module_function

      def dump(value)
        case value
        when Hash then dump_hash(value)
        when Array then "[#{value.map { |v| dump(v) }.join(',')}]"
        when Float then dump_float(value)
        when Integer, true, false, nil then value.to_json
        when String then JSON.generate(value)
        else raise ArgumentError, "Type non canonique : #{value.class}"
        end
      end

      def digest(value)
        Digest::SHA256.hexdigest(dump(value))
      end

      def deep_freeze(value)
        case value
        when Hash then value.each_value { |v| deep_freeze(v) }
        when Array then value.each { |v| deep_freeze(v) }
        end
        value.freeze
      end

      def deep_copy(value)
        case value
        when Hash then value.to_h { |k, v| [k.dup.freeze, deep_copy(v)] }
        when Array then value.map { |v| deep_copy(v) }
        when String then value.dup
        else value
        end
      end

      def dump_hash(hash)
        hash.each_key { |k| raise ArgumentError, "Clé non chaîne : #{k.inspect}" unless k.is_a?(String) }
        pairs = hash.keys.sort_by(&:bytes).map { |k| "#{JSON.generate(k)}:#{dump(hash[k])}" }
        "{#{pairs.join(',')}}"
      end
      private_class_method :dump_hash

      def dump_float(float)
        raise ArgumentError, 'Nombre non fini' unless float.finite?

        float.zero? ? '0.0' : float.to_s
      end
      private_class_method :dump_float
    end
  end
end
