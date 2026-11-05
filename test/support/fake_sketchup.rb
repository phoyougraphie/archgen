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

    def edge?(entity)
      entity.is_a?(Edge)
    end

    def component_instance?(entity)
      entity.is_a?(Instance)
    end

    def identity
      :identity
    end

    def color(red, green, blue)
      Color.new(red, green, blue)
    end
  end

  Color = Struct.new(:red, :green, :blue)

  class Edge
    attr_accessor :hidden
    attr_reader :faces, :ends

    def initialize(ends)
      @ends = ends
      @faces = []
      @hidden = false
    end
  end

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
      points.each_with_index { |p, i| @entities.edge_between(p, points[(i + 1) % points.size]).faces << face }
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

    # Comme le natif : arêtes et faces sont parcourues ensemble.
    def each(&block)
      (@items + edges).each(&block)
    end

    def edges
      (@edges ||= {}).values
    end

    def edge_between(a, b)
      (@edges ||= {})[[a, b].sort] ||= Edge.new([a, b])
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

  class Definition
    include Attributes
    attr_reader :name, :entities, :persistent_id

    def initialize(name, behaviour, persistent_id)
      @name = name
      @entities = Entities.new(behaviour)
      @persistent_id = persistent_id
    end
  end

  Transformation = Struct.new(:values) do
    def to_a
      values
    end
  end

  IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0].freeze

  class Instance
    include Attributes
    attr_accessor :name, :layer, :locked, :valid, :parent, :swap_corrupts
    attr_writer :transformation
    attr_reader :definition, :transform, :persistent_id

    def initialize(definition, transform, parent, persistent_id)
      @definition = definition
      @transform = transform
      @parent = parent
      @persistent_id = persistent_id
      @transformation = Transformation.new(IDENTITY)
      @valid = true
    end

    def definition=(definition)
      @definition = definition
      @transformation = Transformation.new(IDENTITY.dup.tap { |m| m[12] = 99.0 }) if @swap_corrupts
    end

    attr_reader :transformation

    def locked?
      @locked
    end

    def valid?
      @valid
    end
  end

  class Selection < Array
    def length
      size
    end
  end

  # Document complet pour le service : journalise les appels de transaction.
  class ServiceModel < Model
    attr_reader :operations, :instances, :definition_list, :selection
    attr_accessor :active_path, :valid, :start_result, :commit_result, :abort_result, :fail_insert, :writer_behaviour

    def initialize
      super
      @operations = []
      @instances = []
      @definition_list = []
      @valid = true
      @start_result = true
      @commit_result = true
      @abort_result = true
      @writer_behaviour = {}
      @selection = Selection.new
    end

    def valid?
      @valid
    end

    # Copie comme le fait SketchUp : même définition, attributs recopiés, nouveau PID.
    def copy_instance(source)
      copy = add_instance(source.definition, source.transform)
      copy.attrs.merge!(source.attrs)
      copy
    end

    def start_operation(name, disable_ui)
      @operations << [:start, name, disable_ui]
      @start_result
    end

    def commit_operation
      @operations << [:commit]
      @commit_result
    end

    def abort_operation
      @operations << [:abort]
      @abort_result
    end

    def definitions
      DefinitionsPort.new(self)
    end

    def entities
      RootEntities.new(self)
    end

    def find_entity_by_persistent_id(persistent_id)
      @instances.find { |i| i.persistent_id == persistent_id }
    end

    def add_definition(name)
      Definition.new(name, @writer_behaviour, 5000 + @definition_list.size).tap { |d| @definition_list << d }
    end

    def add_instance(definition, transform)
      raise 'panne d’insertion' if @fail_insert

      Instance.new(definition, transform, self, 1000 + @instances.size).tap { |i| @instances << i }
    end

    def mutation_count
      @instances.size + @definition_list.size + @materials.count + @layers.count
    end
  end

  DefinitionsPort = Struct.new(:model) do
    def add(name)
      model.add_definition(name)
    end
  end

  RootEntities = Struct.new(:model) do
    include Enumerable

    def add_instance(definition, transform)
      model.add_instance(definition, transform)
    end

    def each(&block)
      model.instances.each(&block)
    end
  end
end
