# frozen_string_literal: true

# Génère docs/carte/index.html depuis la source unique docs/CARTE.md.
#   ruby scripts/build_carte.rb                 écrit la page
#   ruby scripts/build_carte.rb --artifact PATH écrit aussi le fragment publiable
require 'json'

module CarteBuilder
  REPO = File.expand_path('..', __dir__)
  SOURCE = File.join(REPO, 'docs', 'CARTE.md')
  TEMPLATE = File.join(REPO, 'docs', 'carte', 'template.html')
  OUTPUT = File.join(REPO, 'docs', 'carte', 'index.html')
  STATUSES = %w[fait code encours afaire bloque].freeze

  module_function

  # Convertit les puces en arbre { label, status?, note?, ref?, children }.
  def parse(markdown)
    root = { 'label' => 'ARCHGEN', 'note' => 'Extension SketchUp de bâtiments paramétriques, V0.1.', 'children' => [] }
    stack = [[-1, root]]
    markdown.each_line.with_index(1) do |line, number|
      next unless (m = line.match(/\A( *)- (.+?)\s*\z/))

      indent = m[1].length
      raise "Ligne #{number} : indentation impaire" if indent.odd?

      node = parse_item(m[2], number)
      stack.pop while stack.last[0] >= indent
      stack.last[1]['children'] << node
      stack << [indent, node]
    end
    root
  end

  def parse_item(text, number)
    node = {}
    if (m = text.match(/\A\[([a-z]+)\] /))
      raise "Ligne #{number} : statut inconnu #{m[1]}" unless STATUSES.include?(m[1])

      node['status'] = m[1]
      text = m.post_match
    end
    if (m = text.match(/\s*\(→ ([^)]+)\)\z/))
      node['ref'] = m[1]
      text = m.pre_match
    end
    label, note = text.split(' — ', 2)
    raise "Ligne #{number} : libellé vide" if label.to_s.strip.empty?

    node['label'] = label.strip
    node['note'] = note.strip if note
    node['children'] = []
    node
  end

  def read_utf8(path)
    File.read(path, mode: 'rb', encoding: 'UTF-8')
  end

  # Fragment sans doctype : la publication Artifact ajoute son propre squelette.
  def fragment
    data = JSON.generate(parse(read_utf8(SOURCE))).gsub('<', '\\u003c')
    read_utf8(TEMPLATE).sub('__CARTE_DATA__') { data }
  end

  def page
    head = %(<!doctype html>\n<html lang="fr">\n<head>\n<meta charset="utf-8">\n) +
           %(<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n</head>\n<body>\n)
    "#{head}#{fragment}</body>\n</html>\n"
  end

  def write(path, content)
    File.binwrite(path, content.encode('UTF-8'))
  end
end

if __FILE__ == $PROGRAM_NAME
  CarteBuilder.write(CarteBuilder::OUTPUT, CarteBuilder.page)
  puts "Écrit #{CarteBuilder::OUTPUT}"
  if (i = ARGV.index('--artifact'))
    CarteBuilder.write(ARGV.fetch(i + 1), CarteBuilder.fragment)
    puts "Écrit #{ARGV.fetch(i + 1)}"
  end
end
