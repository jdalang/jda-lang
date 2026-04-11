import math, time

def v3(x,y,z): return (x,y,z)
def v3add(a,b): return (a[0]+b[0],a[1]+b[1],a[2]+b[2])
def v3sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def v3mul(a,s): return (a[0]*s,a[1]*s,a[2]*s)
def v3dot(a,b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def v3norm(v):
    l=math.sqrt(v3dot(v,v))
    return (v[0]/l,v[1]/l,v[2]/l)

spheres = [
    ((0,-1,8), 2, (255,50,50), 500),
    ((3,0,10), 1.5, (50,50,255), 100),
    ((-3,0,10), 1.5, (50,255,50), 200),
    ((0,2,12), 1, (255,255,50), 1000),
    ((0,-5001,0), 5000, (200,200,200), 10),
]

def intersect(orig, d, s):
    oc = v3sub(orig, s[0])
    a = v3dot(d, d)
    b = 2 * v3dot(oc, d)
    c = v3dot(oc, oc) - s[1]*s[1]
    disc = b*b - 4*a*c
    if disc < 0: return 1e18
    sq = math.sqrt(disc)
    t1 = (-b - sq) / (2*a)
    t2 = (-b + sq) / (2*a)
    if t1 > 0.001: return t1
    if t2 > 0.001: return t2
    return 1e18

def clamp(v): return max(0, min(255, int(v)))

def trace(orig, d):
    closest = 1e18
    hit = -1
    for i, s in enumerate(spheres):
        t = intersect(orig, d, s)
        if t < closest: closest = t; hit = i
    if hit < 0: return (30, 30, 60)
    s = spheres[hit]
    point = v3add(orig, v3mul(d, closest))
    normal = v3norm(v3sub(point, s[0]))
    light_pos = (-5, 5, 0)
    light_dir = v3norm(v3sub(light_pos, point))
    in_shadow = False
    for i, ss in enumerate(spheres):
        if i == hit: continue
        if intersect(point, light_dir, ss) < 1e17: in_shadow = True; break
    ambient = 0.15
    diffuse = specular = 0
    if not in_shadow:
        diffuse = v3dot(normal, light_dir)
        if diffuse < 0: diffuse = 0
        view = v3mul(d, -1)
        half = v3norm(v3add(light_dir, view))
        sv = v3dot(normal, half)
        if sv > 0: specular = sv ** s[3]
    intensity = ambient + 0.7*diffuse + 0.3*specular
    c = s[2]
    return (c[0]*intensity, c[1]*intensity, c[2]*intensity)

W, H = 800, 600
camera = (0, 0, 0)
checksum = 0
t0 = time.monotonic()
for y in range(H):
    for x in range(W):
        px = (x - W/2) / W
        py = -(y - H/2) / W
        d = v3norm((px, py, 1))
        col = trace(camera, d)
        r, g, b = clamp(col[0]), clamp(col[1]), clamp(col[2])
        checksum += r*17 + g*31 + b*53
ms = int((time.monotonic() - t0) * 1000)
print(f"checksum: {checksum}")
print(f"time: {ms} ms")
