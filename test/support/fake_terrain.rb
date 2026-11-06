# frozen_string_literal: true

require_relative 'fake_sketchup'

# Doubles du terrain et du relevé : logique d'appel seulement, la preuve native est H13.
module FakeTerrain
  INCH = 0.0254

  Point = Struct.new(:x, :y, :z)
  Bounds = Struct.new(:max)
  Layer = Struct.new(:visible) { def visible? = visible }

  # Un groupe de terrain ou un obstacle : le double ne fait que répondre aux lectures.
  class Solid
    include FakeSketchUp::Attributes
    attr_accessor :parent, :hidden, :layer, :valid, :bounds
    attr_reader :persistent_id

    def initialize(persistent_id, parent)
      @persistent_id = persistent_id
      @parent = parent
      @hidden = false
      @valid = true
      @layer = Layer.new(true)
      @bounds = Bounds.new(Point.new(0.0, 0.0, 200.0 / INCH))
    end

    def hidden? = hidden
    def valid? = valid
  end

  # Le natif est un double : Solid passe pour un groupe.
  module Host
    module_function

    def point(x, y, z) = FakeSketchUp::Host.point(x, y, z)
    def vector(x, y, z) = [x, y, z]
    def group?(entity) = entity.is_a?(Solid) || FakeSketchUp::Host.group?(entity)
    def component_instance?(entity) = entity.is_a?(FakeSketchUp::Instance)
    def face?(entity) = FakeSketchUp::Host.face?(entity)
    def edge?(entity) = FakeSketchUp::Host.edge?(entity)
    def identity = FakeSketchUp::Host.identity
    def transformation(matrix) = FakeSketchUp::Host.transformation(matrix)
    def color(red, green, blue) = FakeSketchUp::Host.color(red, green, blue)
  end

  # Le modèle répond aux rayons par le bloc fourni et les compte.
  class RayModel < FakeSketchUp::ServiceModel
    attr_accessor :ray_answer, :ray_count, :solids, :rays

    def initialize
      super
      @solids = []
      @rays = []
      @ray_count = 0
    end

    def raytest(ray, wysiwyg)
      raise 'wysiwyg doit rester vrai' unless wysiwyg

      @ray_count += 1
      @rays << ray
      @ray_answer.call(ray[0])
    end

    def find_entity_by_persistent_id(persistent_id)
      @solids.find { |s| s.persistent_id == persistent_id } || super
    end
  end
end
