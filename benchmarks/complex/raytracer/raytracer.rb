V3 = Struct.new(:x, :y, :z)

def v3(x,y,z) = V3.new(x,y,z)
def v3add(a,b) = V3.new(a.x+b.x, a.y+b.y, a.z+b.z)
def v3sub(a,b) = V3.new(a.x-b.x, a.y-b.y, a.z-b.z)
def v3mul(a,s) = V3.new(a.x*s, a.y*s, a.z*s)
def v3dot(a,b) = a.x*b.x + a.y*b.y + a.z*b.z
def v3norm(v)
  l = Math.sqrt(v3dot(v,v))
  V3.new(v.x/l, v.y/l, v.z/l)
end

Sphere = Struct.new(:center, :radius, :color, :specular)

SPHERES = [
  Sphere.new(v3(0,-1,8), 2, v3(255,50,50), 500),
  Sphere.new(v3(3,0,10), 1.5, v3(50,50,255), 100),
  Sphere.new(v3(-3,0,10), 1.5, v3(50,255,50), 200),
  Sphere.new(v3(0,2,12), 1, v3(255,255,50), 1000),
  Sphere.new(v3(0,-5001,0), 5000, v3(200,200,200), 10),
]

def intersect(orig, dir, s)
  oc = v3sub(orig, s.center)
  a = v3dot(dir, dir)
  b = 2 * v3dot(oc, dir)
  c = v3dot(oc, oc) - s.radius * s.radius
  disc = b*b - 4*a*c
  return 1e18 if disc < 0
  sq = Math.sqrt(disc)
  t1 = (-b - sq) / (2*a)
  t2 = (-b + sq) / (2*a)
  return t1 if t1 > 0.001
  return t2 if t2 > 0.001
  1e18
end

def clamp(v) = [[0, v.to_i].max, 255].min

def trace(orig, dir)
  closest = 1e18; hit = -1
  SPHERES.each_with_index do |s, i|
    t = intersect(orig, dir, s)
    if t < closest; closest = t; hit = i; end
  end
  return v3(30, 30, 60) if hit < 0
  s = SPHERES[hit]
  point = v3add(orig, v3mul(dir, closest))
  normal = v3norm(v3sub(point, s.center))
  light_dir = v3norm(v3sub(v3(-5, 5, 0), point))
  in_shadow = false
  SPHERES.each_with_index do |ss, i|
    next if i == hit
    if intersect(point, light_dir, ss) < 1e17; in_shadow = true; break; end
  end
  ambient = 0.15; diffuse = 0.0; specular = 0.0
  unless in_shadow
    diffuse = v3dot(normal, light_dir)
    diffuse = 0 if diffuse < 0
    view = v3mul(dir, -1)
    half = v3norm(v3add(light_dir, view))
    sv = v3dot(normal, half)
    specular = sv ** s.specular if sv > 0
  end
  intensity = ambient + 0.7*diffuse + 0.3*specular
  c = s.color
  v3(c.x*intensity, c.y*intensity, c.z*intensity)
end

w, h = 800, 600
camera = v3(0, 0, 0)
checksum = 0
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
h.times do |y|
  w.times do |x|
    px = (x - w/2.0) / w.to_f
    py = -(y - h/2.0) / w.to_f
    dir = v3norm(v3(px, py, 1))
    col = trace(camera, dir)
    r, g, b = clamp(col.x), clamp(col.y), clamp(col.z)
    checksum += r*17 + g*31 + b*53
  end
end
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
puts "checksum: #{checksum}"
puts "time: #{ms} ms"
