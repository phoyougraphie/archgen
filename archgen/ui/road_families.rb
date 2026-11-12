# frozen_string_literal: true

module Archgen
  module UI
    # Familles des préréglages de voirie (AG-147) : rangement d'affichage seulement. Le fichier de
    # préréglages ne change pas ; un préréglage absent de la liste tombe dans « Autres ».
    module RoadFamilies
      FAMILIES = [
        ['Ville', %w[ville boulevard mixte arret-bus]],
        ['Route et campagne', %w[autoroute nationale campagne rural]],
        ['Rail et tram', %w[tram fer]],
        ['Piétons et vélos', %w[verte pieton]],
        ['Eau', %w[canal riviere fleuve]],
        ['Côte', %w[falaises dunes plage]]
      ].freeze
      OTHER = 'Autres'

      module_function

      def family(id)
        found = FAMILIES.find { |_label, ids| ids.include?(id) }
        found ? found.first : OTHER
      end

      # [{ 'label' => …, 'ids' => [...] }] dans l'ordre des familles, sans famille vide.
      def group(ids)
        known = FAMILIES.map { |label, members| [label, members & ids] }
        others = ids.reject { |id| FAMILIES.any? { |_label, members| members.include?(id) } }
        (known + [[OTHER, others]]).filter_map { |label, members| { 'label' => label, 'ids' => members } unless members.empty? }
      end
    end
  end
end
