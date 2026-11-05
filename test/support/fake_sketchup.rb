# frozen_string_literal: true

# Doubles des ports du writer. Ils vérifient la logique d'appel, jamais le natif :
# seule la recette H02 prouve le comportement réel dans SketchUp.
module FakeSketchUp
  Vector = Struct.new(:x, :y, :z)

  module Host
    module_function

    def point(x, y, z)
      [x, y, z]
    end

    def face?(entity)
      entity.is_a?(Face)
    end

    def color(red, green, blue)
      Color.new(red, green, blue)
    end
  end

  Color = Struct.new(:red, :green, :blue)

  class Face
    attr_accessor :material
    attr_reader :points, :reversals

    def initialize(points, flipped: false)
      @points = points
      @flipped = flipped
      @reversals = 0
    end

    def normal
      total = [0.0, 0.0, 0.0]
      @points.each_with_index do |p, i|
        q = @points[(i + 1) % @points.size]
        total[0] += (p[1] - q[1]) * (p[2] + q[2])
        total[1] += (p[2] - q[2]) * (p[0] + q[0])
        total[2] += (p[0] - q[0]) * (p[1] + q[1])
      end
      sign = @flipped ? -1.0 : 1.0
      Vector.new(total[0] * sign, total[1] * sign, total[2] * sign)
    end

    def reverse!
      @flipped = !@flipped
      @reversals += 1
    end
  end

  class Builder
    def initialize(entities, behaviour)
      @entities = entities
      @behaviour = behaviour
    end

    def add_face(points)
      return nil if @behaviour[:reject_faces]

      face = Face.new(points, flipped: @behaviour[:flip_all])
      @entities.items << face
      face
    end
  end

  class Entities
    include Enumerable
    attr_reader :items, :behaviour

    def initialize(behaviour = {})
      @items = []
      @behaviour = behaviour
    end

    def length
      @items.length
    end

    def each(&block)
      @items.each(&block)
    end

    def add_group
      Group.new(@behaviour).tap { |g| @items << g }
    end

    def build
      @in_build = true
      yield Builder.new(self, @behaviour)
      @items << Face.new([[0, 0, 0], [1, 0, 0], [0, 1, 0]]) if @behaviour[:extra_face]
    ensure
      @in_build = false
    end
  end

  class Group
    attr_accessor :name, :layer
    attr_reader :entities

    def initialize(behaviour)
      @entities = Entities.new(behaviour)
    end
  end

  module Attributes
    def attrs
      @attrs ||= {}
    end

    def set_attribute(dictionary, key, value)
      attrs[[dictionary, key]] = value
    end

    def get_attribute(dictionary, key)
      attrs[[dictionary, key]]
    end
  end

  class Material
    include Attributes
    attr_accessor :name, :color

    def initialize(name)
      @name = name
    end
  end

  class Tag
    include Attributes
    attr_accessor :name

    def initialize(name)
      @name = name
    end
  end

  class Collection
    include Enumerable

    def initialize(type)
      @type = type
      @items = []
    end

    def each(&block)
      @items.each(&block)
    end

    def [](name)
      @items.find { |item| item.name == name }
    end

    def add(name)
      existing = self[name]
      return existing if existing

      @type.new(name).tap { |item| @items << item }
    end
  end

  # Volontairement sans start_operation : un appel de transaction ferait échouer le test.
  class Model
    attr_reader :materials, :layers

    def initialize
      @materials = Collection.new(Material)
      @layers = Collection.new(Tag)
    end
  end
end
