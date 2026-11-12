# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Garde unique des écritures : une opération, jamais imbriquée, abandon appelé une
      # seule fois, restauration contrôlée. Après un abandon, le document est comparé à
      # son relevé initial : un écart est un incident bloquant, jamais un succès.
      class TransactionGuard
        def initialize
          @active = false
        end

        # instance : la racine visée, nil pour une création. Retourne un Result.
        def run(model, name, instance: nil)
          return failure('operation_in_progress') if @active

          @active = true
          begin
            record = capture(model, instance)
            return failure('operation_not_started') unless start(model, name)

            execute(model, record, instance) { yield }
          ensure
            @active = false
          end
        end

        private

        def execute(model, record, instance)
          finished = false
          begin
            value = yield
            finished = true
            return Core::Result.ok(value) if commit(model)

            restore(model, record, instance, 'commit_failed', nil)
          rescue StandardError => e
            finished = true
            restore(model, record, instance, 'write_failed', e)
          ensure
            # Une exception hors StandardError traverse la garde sans laisser d'opération ouverte.
            abort_operation(model) unless finished
          end
        end

        def start(model, name)
          model.start_operation(name, true)
        rescue StandardError
          false
        end

        def commit(model)
          model.commit_operation
        rescue StandardError
          false
        end

        def abort_operation(model)
          model.abort_operation
        rescue StandardError
          false
        end

        def restore(model, record, instance, reason, error)
          params = error_params(error)
          return failure('abort_failed', cause: reason, **params) unless abort_operation(model)

          differences = differences(record, capture(model, instance))
          return failure('restore_incomplete', cause: reason, differences: differences, **params) unless differences.empty?

          failure(reason, **params)
        end

        # Le message d'une exception native peut contenir des chemins personnels.
        def error_params(error)
          return {} unless error

          params = { error: error.class.name }
          params[:detail] = error.message if error.is_a?(WriteError)
          params
        end

        def capture(model, instance)
          state = { 'definitions' => model.definitions.length, 'materials' => model.materials.count, 'layers' => model.layers.count }
          state['target'] = instance_state(instance) if instance
          state
        end

        def instance_state(instance)
          return :deleted unless instance.valid?

          metadata = ComponentRepository::KEYS.map { |key| instance.get_attribute(ComponentRepository::DICTIONARY, key) } +
                     ComponentRepository::SITE_KEYS.map { |key| instance.get_attribute(ComponentRepository::SITE_DICTIONARY, key) } +
                     EnsembleRepository::KEYS.map { |key| instance.get_attribute(EnsembleRepository::DICTIONARY, key) }
          [instance.definition, instance.transformation.to_a, metadata]
        end

        def differences(before, after)
          before.keys.reject { |key| before[key] == after[key] }
        end

        def failure(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_WRITE', '/model', reason: reason, **params)])
        end
      end
    end
  end
end
