# frozen_string_literal: true

require_relative '../test_helper'
require File.expand_path('../../scripts/build_carte', __dir__)

# Garantit que la carte mentale reste la source de contexte fiable.
class CarteTest < Minitest::Test
  def tree
    @tree ||= CarteBuilder.parse(read_utf8('docs', 'CARTE.md'))
  end

  def nodes(node = tree)
    [node] + node['children'].flat_map { |c| nodes(c) }
  end

  def test_generated_page_is_up_to_date
    assert_equal CarteBuilder.page, read_utf8('docs', 'carte', 'index.html'),
                 'Page périmée : lancer bundle exec rake carte'
  end

  def test_every_ticket_of_tasks_has_a_status
    expected = read_utf8('planning', 'TASKS.md').scan(/\*\*(AG-\d{3})/).flatten
    assert_equal 50, expected.size
    found = nodes.select { |n| n['label'].match?(/\AAG-\d{3}/) }
    assert_equal expected, found.map { |n| n['label'][/AG-\d{3}/] }
    found.each { |n| refute_nil n['status'], "#{n['label']} sans statut" }
  end

  def test_every_cited_document_exists
    nodes.filter_map { |n| n['ref'] }.each do |ref|
      assert File.exist?(repo_path(ref)), "Référence absente : #{ref}"
    end
  end

  def test_all_test_ids_and_requirements_are_mapped
    labels = nodes.map { |n| n['label'] }
    ids = (1..21).map { |i| format('U%02d', i) } + (1..17).map { |i| format('H%02d', i) }
    ids += (1..9).map { |i| format('P%02d', i) }
    ids.each { |id| assert(labels.any? { |l| l.start_with?(id) }, "#{id} absent de la carte") }
  end
end
