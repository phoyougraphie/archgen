# frozen_string_literal: true

module Archgen
  module UI
    # Observateurs natifs, attachés seulement tant que le panneau est ouvert. Ils ne font
    # que prévenir : aucun n'écrit dans le modèle et aucun ne démarre d'opération.
    module PanelObservers
      class SelectionWatcher < ::Sketchup::SelectionObserver
        def initialize(&callback)
          super()
          @callback = callback
        end

        def onSelectionBulkChange(_selection)
          @callback.call
        end

        def onSelectionCleared(_selection)
          @callback.call
        end
      end

      class ModelWatcher < ::Sketchup::ModelObserver
        def initialize(&callback)
          super()
          @callback = callback
        end

        def onTransactionUndo(_model)
          @callback.call('undo')
        end

        def onTransactionRedo(_model)
          @callback.call('redo')
        end

        def onPostSaveModel(_model)
          @callback.call('saved')
        end
      end

      class AppWatcher < ::Sketchup::AppObserver
        def initialize(&callback)
          super()
          @callback = callback
        end

        def onNewModel(model)
          @callback.call(model)
        end

        def onOpenModel(model)
          @callback.call(model)
        end
      end
    end
  end
end
