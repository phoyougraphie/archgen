# frozen_string_literal: true

# Outils de U27 : réseaux de voies droites et contrôles de surface vus de dessus.
module RoadNet
  C = Archgen::Composition

  module_function

  def preset(id)
    C.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def road(id, points, profile = 'ville', radii: nil)
    { 'id' => id, 'road' => { 'trace' => { 'points_m' => points, 'radii_m' => radii || Array.new(points.size - 2, 20) },
                              'profile' => profile.is_a?(String) ? preset(profile) : profile } }
  end

  def network(*roads, junctions: nil)
    tree = { 'roads' => roads }
    tree['junctions'] = junctions if junctions
    tree
  end

  def build(tree)
    settings = C.road_network_intake.settings(tree)
    return settings unless settings.ok?

    Archgen::Core::RoadNetworkEngine.call(settings.value, bands: C.road_bands, items: C.road_items)
  end

  def surface(plan)
    plan['nodes'][0]['children'][0]['primitive']
  end

  # Emprise d'une voie droite de p0 à p1 : origine, direction, u mini et maxi (u à gauche), longueur.
  def strip(p0, p1, profile)
    effective = C.road_profile_intake.profile(profile.is_a?(String) ? preset(profile) : profile).value
    width = effective['bands'].sum { |b| b['width_m'] }
    d = [p1[0] - p0[0], p1[1] - p0[1]]
    l = Math.hypot(*d)
    [p0, d.map { |c| c / l }, -width / 2.0, width / 2.0, l]
  end

  def inside_strip?(strips, x, y, margin)
    strips.any? do |o, d, u0, u1, l|
      t = ((x - o[0]) * d[0]) + ((y - o[1]) * d[1])
      u = (-(x - o[0]) * d[1]) + ((y - o[1]) * d[0])
      t > margin && t < l - margin && u > u0 + margin && u < u1 - margin
    end
  end

  # Faces non verticales, projetées sur le plan.
  def top_polygons(plan)
    surf = surface(plan)
    v = surf['vertices']
    surf['faces'].map { |f| f['indices'].map { |i| v[i] } }.select { |pts| area(pts).abs > 1e-9 }
  end

  def area(pts)
    pts.each_index.sum { |i| (pts[i][0] * pts[(i + 1) % pts.size][1]) - (pts[(i + 1) % pts.size][0] * pts[i][1]) } / 2.0
  end

  def in_polygon?(x, y, pts)
    inside = false
    j = pts.size - 1
    pts.each_with_index do |p, i|
      q = pts[j]
      inside = !inside if ((p[1] > y) != (q[1] > y)) && (x < (((q[0] - p[0]) * (y - p[1])) / (q[1] - p[1])) + p[0])
      j = i
    end
    inside
  end

  # Points d'une grille dans les emprises couverts 0 fois (trou) ou 2 fois et plus (recouvrement).
  def coverage_defects(plan, strips, box, step: 0.37)
    polys = top_polygons(plan).map { |pts| [pts, pts.map(&:first).minmax, pts.map { |p| p[1] }.minmax] }
    out = []
    x0, y0, x1, y1 = box
    (0..((x1 - x0) / step).floor).each do |i|
      x = x0 + 0.0137 + (i * step)
      (0..((y1 - y0) / step).floor).each do |j|
        y = y0 + 0.0071 + (j * step)
        next unless inside_strip?(strips, x, y, 0.02)

        n = polys.count { |pts, (ax, bx), (ay, by)| x.between?(ax, bx) && y.between?(ay, by) && in_polygon?(x, y, pts) }
        out << [x.round(2), y.round(2), n] unless n == 1
      end
    end
    out
  end

  # Arêtes portées par plus de deux faces, et arêtes libres à l'intérieur des emprises.
  def edge_defects(plan, strips)
    surf = surface(plan)
    v = surf['vertices']
    count = Hash.new(0)
    surf['faces'].each do |f|
      ix = f['indices']
      ix.each_with_index { |a, i| count[[a, ix[(i + 1) % ix.size]].sort] += 1 }
    end
    over = count.count { |_, n| n > 2 }
    free = count.select { |_, n| n == 1 }.keys.map { |a, b| v[a].zip(v[b]).map { |p, q| (p + q) / 2 } }
    [over, free.count { |m| inside_strip?(strips, m[0], m[1], 0.05) }]
  end
  # Faces verticales tournées vers le haut de la marche : la surface devant la face doit être plus basse
  # que derrière. Retourne les centres fautifs.
  def misfacing_walls(plan, box)
    surf = surface(plan)
    v = surf['vertices']
    tops = top_polygons(plan)
    x0, y0, x1, y1 = box
    surf['faces'].filter_map do |f|
      pts = f['indices'].map { |i| v[i] }
      n = normal(pts)
      len = Math.hypot(n[0], n[1])
      next if len < 1e-9 || n[2].abs > 1e-6 * Math.sqrt(n.sum { |c| c * c })

      c = (0..2).map { |k| pts.sum { |p| p[k] } / pts.size }
      next unless c[0].between?(x0, x1) && c[1].between?(y0, y1)

      front = height(tops, c[0] + (0.05 * n[0] / len), c[1] + (0.05 * n[1] / len))
      back = height(tops, c[0] - (0.05 * n[0] / len), c[1] - (0.05 * n[1] / len))
      next if front.nil? || back.nil?

      c.map { |k| k.round(2) } unless front < back
    end
  end

  def normal(pts)
    n = [0.0, 0.0, 0.0]
    pts.each_with_index do |p, i|
      q = pts[(i + 1) % pts.size]
      n[0] += (p[1] - q[1]) * (p[2] + q[2])
      n[1] += (p[2] - q[2]) * (p[0] + q[0])
      n[2] += (p[0] - q[0]) * (p[1] + q[1])
    end
    n
  end

  def height(tops, x, y)
    hit = tops.find { |pts| in_polygon?(x, y, pts) }
    hit && (hit.sum { |p| p[2] } / hit.size)
  end
end
