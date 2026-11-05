# frozen_string_literal: true

# Accès aux schémas et exemples du dépôt pour les tests.
module TestData
  REPO = File.expand_path('../..', __dir__)

  def self.read(*parts)
    File.read(File.join(REPO, *parts), mode: 'rb', encoding: 'UTF-8')
  end

  def self.json(*parts)
    JSON.parse(read(*parts))
  end

  def self.schemas
    @schemas ||= {
      'draft' => json('schemas', 'building-draft.v1.schema.json'),
      'config' => json('schemas', 'building-config.v1.schema.json'),
      'profile' => json('schemas', 'style-profile.v1.schema.json')
    }
  end

  def self.materials
    @materials ||= json('examples', 'materials.v1.json')['materials']
  end

  def self.intake
    @intake ||= Archgen::Core::Intake.new(schemas)
  end

  def self.building(name)
    json('examples', 'buildings', "#{name}.json")
  end

  def self.profiles
    Dir.glob(File.join(REPO, 'examples', 'profiles', '*.json')).sort.map { |p| JSON.parse(File.read(p, encoding: 'UTF-8')) }
  end
end
