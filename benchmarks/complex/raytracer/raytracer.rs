/* Ray tracer — 800x600, 5 spheres, shadows + diffuse + specular lighting */
use std::time::Instant;

#[derive(Clone, Copy)]
struct Vec3 { x: f64, y: f64, z: f64 }

impl Vec3 {
    fn new(x: f64, y: f64, z: f64) -> Self { Vec3 { x, y, z } }
    fn add(self, b: Vec3) -> Vec3 { Vec3::new(self.x+b.x, self.y+b.y, self.z+b.z) }
    fn sub(self, b: Vec3) -> Vec3 { Vec3::new(self.x-b.x, self.y-b.y, self.z-b.z) }
    fn mul(self, s: f64) -> Vec3 { Vec3::new(self.x*s, self.y*s, self.z*s) }
    fn dot(self, b: Vec3) -> f64 { self.x*b.x + self.y*b.y + self.z*b.z }
    fn norm(self) -> Vec3 { let l = self.dot(self).sqrt(); Vec3::new(self.x/l, self.y/l, self.z/l) }
}

struct Sphere { center: Vec3, radius: f64, color: Vec3, specular: f64 }

fn intersect(orig: Vec3, dir: Vec3, s: &Sphere) -> f64 {
    let oc = orig.sub(s.center);
    let a = dir.dot(dir);
    let b = 2.0 * oc.dot(dir);
    let c = oc.dot(oc) - s.radius * s.radius;
    let disc = b*b - 4.0*a*c;
    if disc < 0.0 { return 1e18; }
    let sq = disc.sqrt();
    let t1 = (-b - sq) / (2.0*a);
    let t2 = (-b + sq) / (2.0*a);
    if t1 > 0.001 { return t1; }
    if t2 > 0.001 { return t2; }
    1e18
}

fn clamp(v: i32) -> i32 { if v < 0 { 0 } else if v > 255 { 255 } else { v } }

fn trace(orig: Vec3, dir: Vec3, spheres: &[Sphere]) -> Vec3 {
    let mut closest = 1e18;
    let mut hit: i32 = -1;
    for i in 0..spheres.len() {
        let t = intersect(orig, dir, &spheres[i]);
        if t < closest { closest = t; hit = i as i32; }
    }
    if hit < 0 { return Vec3::new(30.0, 30.0, 60.0); }
    let hi = hit as usize;
    let point = orig.add(dir.mul(closest));
    let normal = point.sub(spheres[hi].center).norm();
    let light_pos = Vec3::new(-5.0, 5.0, 0.0);
    let light_dir = light_pos.sub(point).norm();

    let mut in_shadow = false;
    for i in 0..spheres.len() {
        if i == hi { continue; }
        if intersect(point, light_dir, &spheres[i]) < 1e17 { in_shadow = true; break; }
    }

    let ambient = 0.15;
    let mut diffuse = 0.0;
    let mut specular = 0.0;
    if !in_shadow {
        diffuse = normal.dot(light_dir);
        if diffuse < 0.0 { diffuse = 0.0; }
        let view = dir.mul(-1.0);
        let half = light_dir.add(view).norm();
        let s = normal.dot(half);
        if s > 0.0 { specular = s.powf(spheres[hi].specular); }
    }
    let intensity = ambient + 0.7 * diffuse + 0.3 * specular;
    let c = spheres[hi].color;
    Vec3::new(c.x * intensity, c.y * intensity, c.z * intensity)
}

fn main() {
    let spheres = vec![
        Sphere { center: Vec3::new(0.0,-1.0,8.0), radius: 2.0, color: Vec3::new(255.0,50.0,50.0), specular: 500.0 },
        Sphere { center: Vec3::new(3.0,0.0,10.0), radius: 1.5, color: Vec3::new(50.0,50.0,255.0), specular: 100.0 },
        Sphere { center: Vec3::new(-3.0,0.0,10.0), radius: 1.5, color: Vec3::new(50.0,255.0,50.0), specular: 200.0 },
        Sphere { center: Vec3::new(0.0,2.0,12.0), radius: 1.0, color: Vec3::new(255.0,255.0,50.0), specular: 1000.0 },
        Sphere { center: Vec3::new(0.0,-5001.0,0.0), radius: 5000.0, color: Vec3::new(200.0,200.0,200.0), specular: 10.0 },
    ];
    let (w, h) = (800, 600);
    let camera = Vec3::new(0.0, 0.0, 0.0);
    let mut checksum: i64 = 0;
    let t0 = Instant::now();
    for y in 0..h {
        for x in 0..w {
            let px = (x as f64 - w as f64 / 2.0) / w as f64;
            let py = -(y as f64 - h as f64 / 2.0) / w as f64;
            let dir = Vec3::new(px, py, 1.0).norm();
            let col = trace(camera, dir, &spheres);
            let r = clamp(col.x as i32);
            let g = clamp(col.y as i32);
            let b = clamp(col.z as i32);
            checksum += (r * 17 + g * 31 + b * 53) as i64;
        }
    }
    let ms = t0.elapsed().as_millis();
    println!("checksum: {}", checksum);
    println!("time: {} ms", ms);
}
