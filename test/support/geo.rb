# frozen_string_literal: true

# Mesures indépendantes du noyau, pour vérifier la géométrie sans réutiliser son code.
module Geo
  module_function

  def sub(a, b)
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
  end

  def cross(a, b)
    [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
  end

  def dot(a, b)
    (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
  end

  def norm(a)
    Math.sqrt(dot(a, a))
  end

  def polygon(primitive, face)
    face['indices'].map { |i| primitive['vertices'][i] }
  end

  # Vecteur de Newell : direction = normale, norme = 2 × aire.
  def area_vector(points)
    total = [0.0, 0.0, 0.0]
    points.each_with_index do |p, i|
      q = points[(i + 1) % points.size]
      total = [total[0] + ((p[1] - q[1]) * (p[2] + q[2])),
               total[1] + ((p[2] - q[2]) * (p[0] + q[0])),
               total[2] + ((p[0] - q[0]) * (p[1] + q[1]))]
    end
    total
  end

  def area(points)
    norm(area_vector(points)) / 2.0
  end

  def unit_normal(points)
    v = area_vector(points)
    n = norm(v)
    [v[0] / n, v[1] / n, v[2] / n]
  end

  def total_area(primitive)
    primitive['faces'].sum { |f| area(polygon(primitive, f)) }
  end

  # Volume signé par le théorème de la divergence (faces en éventail).
  def signed_volume(primitive)
    primitive['faces'].sum do |f|
      pts = polygon(primitive, f)
      (1...(pts.size - 1)).sum { |i| dot(pts[0], cross(pts[i], pts[i + 1])) / 6.0 }
    end
  end

  # Vrai si le segment [a,b] coupe le polygone convexe plan (bords compris).
  def segment_hits?(a, b, points)
    normal = area_vector(points)
    denominator = dot(normal, sub(b, a))
    return false if denominator.abs < 1e-12

    t = dot(normal, sub(points[0], a)) / denominator
    return false if t < -1e-9 || t > 1 + 1e-9

    hit = [a[0] + (t * (b[0] - a[0])), a[1] + (t * (b[1] - a[1])), a[2] + (t * (b[2] - a[2]))]
    points.each_with_index.all? do |p, i|
      q = points[(i + 1) % points.size]
      dot(cross(sub(q, p), sub(hit, p)), normal) >= -1e-9
    end
  end

  def primitive_hit?(primitive, a, b)
    primitive['faces'].any? { |f| segment_hits?(a, b, polygon(primitive, f)) }
  end

  def walk(nodes, &block)
    nodes.each do |node|
      block.call(node)
      walk(node['children'], &block)
    end
  end

  def find_nodes(plan_nodes, category)
    found = []
    walk(plan_nodes) { |n| found << n if n['category'] == category }
    found
  end

  def find_node(plan_nodes, id)
    walk(plan_nodes) { |n| return n if n['id'] == id }
    nil
  end
end
