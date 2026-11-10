# frozen_string_literal: true

module Archgen
  module Core
    # Étagement d'un ensemble : une plateforme par parcelle (docs/TERRAIN_CONTRACT.md). Pur :
    # il reçoit une grille par parcelle et ne connaît pas SketchUp. Le plan d'ensemble n'est pas touché.
    module EnsembleSite
      SCHEMA_VERSION = 1
      KEY_CHARS = 16
      HINT = SurveyGrid::HINT

      module_function

      # Ce qu'il faut relever, avant tout rayon : [{ 'id', 'matrix', 'axes' }].
      def requests(plan, layout, site)
        bend = site['earthwork'] == 'embankment' ? embankment_problem(layout['parcels']) : nil
        return Result.fail([bend]) if bend

        ends = row_ends(layout['parcels'])
        planned = layout['parcels'].map { |parcel| axes_for(parcel, site, ends.fetch(parcel['id'], [])) }
        errors = planned.each_with_index.flat_map { |result, i| result.errors.map { |d| ParcelBuilding.relocate(d, layout['parcels'][i]) } }
        return Result.fail(errors) unless errors.empty?

        points = planned.sum { |result| result.value['xs_m'].size * result.value['ys_m'].size }
        return Result.fail([points_problem(points)]) if points > Limits::ENSEMBLE_SITE_MAX_POINTS

        Result.ok(plan['parcels'].zip(planned).map { |parcel, axes| { 'id' => parcel['id'], 'matrix' => parcel['matrix'], 'axes' => axes.value } })
      end

      def digest(site_plan)
        Canonical.digest(site_plan)
      end

      # grids : { id => SurveyGrid }. root_z_m : le Z de la racine, qui décide de l'étagement.
      def call(settings:, site:, plan:, layout:, grids:, root_z_m:, registry:, intake:, materials:, limits: EnsembleEngine::DEFAULT_LIMITS)
        pairs = plan['parcels'].zip(layout['parcels'])
        prepared = pairs.map { |placed, parcel| prepare(settings, site, parcel, grids.fetch(placed['id']), registry, intake) }
        errors = prepared.flat_map(&:errors)
        return Result.fail(errors.sort_by(&:sort_key)) unless errors.empty?

        parties = parties_for(layout['parcels'], prepared.map { |p| p.value[:assise]['platform_z_m'] }, site)
        built = pairs.each_with_index.map do |(placed, parcel), i|
          parcel_site(site, plan, placed, parcel, grids.fetch(placed['id']), prepared[i].value, materials, parties[i])
        end
        errors = built.flat_map(&:errors)
        return Result.fail(errors.sort_by(&:sort_key)) unless errors.empty?

        assemble(built, settings.dig('trace', 'closed'), plan, grids, root_z_m, limits)
      end

      def axes_for(parcel, site, ends = [])
        xs = [0.0, parcel['width_m'], parcel['delta_left_m'], parcel['width_m'] - parcel['delta_right_m']]
        return SurveyGrid.plan_box(x_min_m: xs.min, x_max_m: xs.max, depth_m: parcel['depth_m'], settings: site) unless site['earthwork'] == 'embankment'

        SurveyGrid.plan_row(x_min_m: xs.min, x_max_m: xs.max, depth_m: parcel['depth_m'], settings: site, left: ends.include?(:left), right: ends.include?(:right))
      end

      # Premier et dernier de chaque rangée : leur côté extérieur n'a pas de voisin.
      def row_ends(parcels)
        out = Hash.new { |hash, key| hash[key] = [] }
        parcels.group_by { |parcel| row_of(parcel) }.each_value do |row|
          out[row.first['id']] << :left
          out[row.last['id']] << :right
        end
        out
      end

      def row_of(parcel)
        parcel['id'].split('/').first
      end
      private_class_method :row_of

      # AG-109 : façades en talus et écart de plateforme avec la voisine de droite (même rangée).
      def parties_for(parcels, platforms, site)
        return parcels.map { nil } unless site['earthwork'] == 'embankment'

        ends = row_ends(parcels)
        parcels.each_with_index.map do |parcel, i|
          mine = ends.fetch(parcel['id'], [])
          sloped = %w[front rear] + (mine.include?(:right) ? %w[right] : []) + (mine.include?(:left) ? %w[left] : [])
          following = parcels[i + 1]
          right_dz = following && row_of(following) == row_of(parcel) ? Quant.q(platforms[i + 1] - platforms[i]) : nil
          { sloped: Geometry::FACADE_ORDER & sloped, right_dz: right_dz }
        end
      end
      private_class_method :parties_for

      def prepare(settings, site, parcel, grid, registry, intake)
        ready = ParcelBuilding.prepare(settings, parcel, registry: registry, intake: intake)
        return ready unless ready.ok?

        footprint = Geometry::FootprintSolver.trapezoid(width_m: parcel['width_m'], depth_m: parcel['depth_m'], delta_left_m: parcel['delta_left_m'], delta_right_m: parcel['delta_right_m'])
        assise = SiteAssise.for_ring(grid, site, ring: footprint.ring)
        return relocated(assise, parcel) unless assise.ok?

        Result.ok({ ready: ready.value, footprint: footprint, assise: assise.value })
      end
      private_class_method :prepare

      def parcel_site(site, plan, placed, parcel, grid, prepared, materials, party)
        planned = Geometry::SitePlanner.call(plan: plan['definitions'].fetch(placed['definition_id']), config: prepared[:ready].config.to_h, grid: grid, settings: site,
                                             assise: prepared[:assise], materials: materials, footprint: prepared[:footprint], passage: parcel['porch'], party: party)
        planned.ok? ? Result.ok(planned.value, planned.diagnostics.map { |d| ParcelBuilding.relocate(d, parcel) }) : relocated(planned, parcel)
      end
      private_class_method :parcel_site

      def relocated(result, parcel)
        Result.fail(result.errors.map { |d| ParcelBuilding.relocate(d, parcel) })
      end
      private_class_method :relocated

      def assemble(built, closed, plan, grids, root_z_m, limits)
        definitions = {}
        parcels = plan['parcels'].zip(built).map do |placed, result|
          metrics = result.value['metrics']
          id = "site/#{Canonical.digest(result.value['nodes'])[0, KEY_CHARS]}"
          definitions[id] ||= definition_for(result.value)
          parcel_entry(placed['id'], id, metrics, root_z_m)
        end
        metrics = metrics_for(built.map { |result| result.value['metrics'] }, parcels, definitions, closed, grids)
        budget = budget_problem(metrics, plan['metrics'], limits)
        return Result.fail([budget]) if budget

        site_plan = { 'schema_version' => SCHEMA_VERSION, 'units' => 'm', 'definitions' => definitions, 'parcels' => parcels, 'metrics' => metrics }
        Result.ok(Canonical.deep_freeze(site_plan), built.flat_map(&:diagnostics).sort_by(&:sort_key))
      end
      private_class_method :assemble

      def definition_for(parcel_plan)
        { 'schema_version' => SCHEMA_VERSION, 'units' => 'm', 'nodes' => parcel_plan['nodes'],
          'metrics' => { 'site_face_count' => parcel_plan['metrics']['site_face_count'] } }
      end
      private_class_method :definition_for

      def parcel_entry(id, definition_id, metrics, root_z_m)
        {
          'id' => id, 'site_definition_id' => definition_id, 'level_m' => Quant.q(metrics['platform_z_m'] - root_z_m),
          'platform_z_m' => metrics['platform_z_m'], 'terrain_min_z_m' => metrics['terrain_min_z_m'], 'terrain_max_z_m' => metrics['terrain_max_z_m'],
          'cut_max_m' => metrics['cut_max_m'], 'fill_max_m' => metrics['fill_max_m'],
          'door_gap_m' => metrics['door_gap_m'], 'buried_opening_count' => metrics['buried_opening_count']
        }
      end
      private_class_method :parcel_entry

      def metrics_for(all, parcels, definitions, closed, grids)
        platforms = all.map { |m| m['platform_z_m'] }
        {
          'parcel_count' => parcels.size,
          'site_definition_count' => definitions.size,
          'unique_site_face_count' => definitions.values.sum { |d| d['metrics']['site_face_count'] },
          'expanded_site_face_count' => all.sum { |m| m['site_face_count'] },
          'survey_point_count' => grids.values.sum { |grid| grid.xs.size * grid.ys.size },
          'platform_min_z_m' => platforms.min,
          'platform_max_z_m' => platforms.max,
          'max_step_m' => max_step(parcels, closed),
          'cut_max_m' => all.map { |m| m['cut_max_m'] }.max,
          'fill_max_m' => all.map { |m| m['fill_max_m'] }.max,
          'cut_volume_m3' => Quant.q(all.sum { |m| m['cut_volume_m3'] }),
          'fill_volume_m3' => Quant.q(all.sum { |m| m['fill_volume_m3'] }),
          'buried_opening_count' => all.sum { |m| m['buried_opening_count'] }
        }
      end
      private_class_method :metrics_for

      # Entre voisines d'une même rangée ; un contour fermé rejoint sa première parcelle.
      def max_step(parcels, closed)
        steps = parcels.group_by { |parcel| parcel['id'].split('/').first }.values.flat_map do |row|
          chain = closed && row.size > 1 ? row + [row.first] : row
          chain.each_cons(2).map { |a, b| (a['platform_z_m'] - b['platform_z_m']).abs }
        end
        Quant.q(steps.max || 0.0)
      end
      private_class_method :max_step

      def budget_problem(metrics, building, limits)
        unique = building['unique_face_count'] + metrics['unique_site_face_count']
        expanded = building['expanded_face_count'] + metrics['expanded_site_face_count']
        return budget('total_faces', limits[:unique], unique) if unique > limits[:unique]

        expanded > limits[:expanded] ? budget('total_faces', limits[:expanded], expanded) : nil
      end
      private_class_method :budget_problem

      def budget(reason, limit, value)
        Diagnostic.error('E_SITE_BUDGET', '/site/survey/step_m', reason: reason, limit: limit, value: value, hint: HINT)
      end
      private_class_method :budget

      def points_problem(points)
        budget('survey_points', Limits::ENSEMBLE_SITE_MAX_POINTS, points)
      end
      private_class_method :points_problem

      # AG-109 : talus seulement sur une rangée droite de parcelles rectangulaires ; un coude ou un îlot
      # donnerait des talus voisins qui ne se rejoignent pas.
      def embankment_problem(parcels)
        bent = parcels.reject { |p| p['delta_left_m'].abs < Quant::EPSILON && p['delta_right_m'].abs < Quant::EPSILON }
        return nil if bent.empty?

        Diagnostic.error('E_STREET_SITE', '/site/earthwork', reason: 'embankment_bend', ids: bent.map { |p| p['id'] }.first(5))
      end
      private_class_method :embankment_problem
    end
  end
end
